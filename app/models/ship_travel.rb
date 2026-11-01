# app/models/ship_travel.rb
class ShipTravel < ApplicationRecord
  attr_accessor :request_replayed, :request_outcome

  belongs_to :user_ship
  belongs_to :from_location, class_name: 'Location'
  belongs_to :to_location,   class_name: 'Location'

  validates :travel_guid, presence: true, uniqueness: true
  validate :timing_contract

  def timing_contract
    errors.add(:base,'Invalid travel timing or pause metadata') if TravelState.new(self,tick:0).invalid?
  end

  # Which RabbitMQ broker this travel's eventual ShipArrival event belongs to.
  # Chosen when the travel begins and preserved for the rest of its lifetime,
  # because the arrival is published long after the originating request is gone.
  before_validation :normalize_rabbitmq_environment
  validates :rabbitmq_environment,
    inclusion: {
      in: RabbitmqConnection::ENVIRONMENTS,
      message: "must be one of: #{RabbitmqConnection::ENVIRONMENTS.join(', ')}"
    }

  # "Active" means in-flight and not paused
  scope :active, -> {
    where(is_paused: false, completed_at_tick: nil).where('arrival_tick >= ?', Tick.current)
  }

  scope :in_flight_now, ->(tick = Tick.current) {
    where(is_paused: false, completed_at_tick: nil)
      .where('departure_tick <= ? AND arrival_tick >= ?', tick, tick)
  }

  scope :completed, -> { where.not(completed_at_tick: nil) }

  scope :stale_after_arrival, ->(tick = Tick.current) {
    where(is_paused: false).where.not(completed_at_tick: nil)
      .where("arrival_tick > 0")
      .where("arrival_tick <= ?", tick)
  }

  # Optional: narrow by shard or star system
  scope :for_shard, ->(shard) {
    joins(:user_ship).where(user_ships: { shard_name: shard }) if shard.present?
  }

scope :for_star_system, ->(name) {
  next all if name.blank?
  joins(:from_location, :to_location)
    .where(
      "from_locations_ship_travels.star_system_name = :n OR to_locations_ship_travels.star_system_name = :n",
      n: name
    )
}

scope :interdictable_now_sql, ->(tick = Tick.current) {
  window_sql = "CEIL((total_duration_ticks * interdict_window_percent)::numeric / 100.0)"

  where(is_paused: false)
    .where(completed_at_tick: nil)
    .where(
      [
        "((:tick BETWEEN departure_tick AND (departure_tick + #{window_sql} - 1)) OR
          (:tick BETWEEN (arrival_tick - #{window_sql} + 1) AND arrival_tick))",
        { tick: tick }
      ]
    )
}

  # For your existing association on UserShip:
  # has_one :active_travel, -> { active }, class_name: 'ShipTravel'

  def duration_ticks
    total_duration_ticks.to_i.positive? ? total_duration_ticks : (arrival_tick.to_i - departure_tick.to_i)
  end

  def window_ticks
    ((duration_ticks * interdict_window_percent) / 100.0).ceil
  end

  def seconds_remaining(current_tick)
    [arrival_tick - current_tick, 0].max * Tick.seconds_per_tick
  end

  def departure_window_range
    s = departure_tick
    e = [departure_tick + window_ticks - 1, arrival_tick].min
    (s..e)
  end

  def arrival_window_range
    s = [arrival_tick - window_ticks + 1, departure_tick].max
    e = arrival_tick
    (s..e)
  end

  # returns :departure, :arrival, or nil
  def current_interdictable_phase(current_tick = Tick.current)
    return nil if is_paused || completed_at_tick.present?
    return :departure if departure_window_range.cover?(current_tick)
    return :arrival   if arrival_window_range.cover?(current_tick)
    nil
  end

  def distance_from_arrival_in_ticks(current_tick = Tick.current)
    [arrival_tick - current_tick, 0].max
  end

  def distance_from_departure_in_ticks(current_tick = Tick.current)
    [current_tick - departure_tick, 0].max
  end

  def progress_fraction(current_tick = Tick.current)
    dur = duration_ticks.to_f
    return 0.0 if dur <= 0
    (distance_from_departure_in_ticks(current_tick) / dur).clamp(0.0, 1.0)
  end

  def due_for_arrival?(current_tick = Tick.current)
    !is_paused && completed_at_tick.nil? && arrival_tick.to_i.positive? && arrival_tick <= current_tick
  end

  def self.cleanup_stale_after_arrival!(tick = Tick.current)
    cleaned_count = 0

    stale_after_arrival(tick).find_each do |travel|
      travel.cleanup_stale_after_arrival!(tick)
      cleaned_count += 1
    end

    Rails.logger.info("Cleaned #{cleaned_count} stale ShipTravel records after tick #{tick}.") if cleaned_count.positive?
    cleaned_count
  end

  # --- Interdiction controls ---

  # Pauses travel and records remaining distance to arrival.
  # Idempotent: calling when already paused simply returns self.
  def interdict!(current_tick = Tick.current, enforce_window: false)
    TravelLifecycle.with_ship(user_ship) do
      lock!
      if TravelState.new(self,tick:current_tick).invalid?
        raise TravelLifecycle::Error.new('invalid_state','Travel needs review before interdiction.')
      end
      next self if is_paused
      if completed_at_tick || (enforce_window && current_interdictable_phase(current_tick).nil?)
        raise TravelLifecycle::Error.new('invalid_state','Travel is not in an interdictable window.')
      end
      update!(is_paused:true,paused_at_tick:current_tick,
        remaining_ticks_from_arrival:distance_from_arrival_in_ticks(current_tick),
        interdiction_count:interdiction_count+1,last_interdicted_tick:current_tick,arrival_tick:0)
      user_ship.update!(status:'interdicted')
      self
    end
  end

  def resume!(current_tick = Tick.current)
    TravelLifecycle.with_ship(user_ship) do
      lock!
      unless TravelState.new(self,tick:current_tick).valid_pause? && !TravelState.new(self,tick:current_tick).invalid?
        raise TravelLifecycle::Error.new('invalid_state','Travel has invalid pause metadata; review is required.')
      end
      rem=[remaining_ticks_from_arrival,1].max
      update!(is_paused:false,paused_at_tick:nil,departure_tick:current_tick,
        arrival_tick:TravelLifecycle.deadline!(current_tick,rem),total_duration_ticks:rem)
      user_ship.update!(status:'in_transit')
      self
    end
  end

  def cleanup_after_arrival!(current_tick = Tick.current)
    destroy_for_lifecycle!(reason: "arrival", current_tick: current_tick)
  end

  def cleanup_after_cancellation!(current_tick = Tick.current)
    TravelLifecycle.with_ship(user_ship) do
      TravelRequestReceipt.lock_guid!(travel_guid)
      lock!
      if is_paused || completed_at_tick || arrival_tick.to_i < current_tick
        raise TravelLifecycle::Error.new('invalid_state','Journey is not eligible for cancellation.')
      end
      TravelRequestReceipt.finish!(self,'cancelled',current_tick)
      destroy_for_lifecycle!(reason:'cancelled',current_tick:current_tick,ship_status:'aimlessly floating in space')
    end
  end

  def cleanup_stale_after_arrival!(current_tick = Tick.current)
    TravelLifecycle.with_ship(user_ship) do
      TravelRequestReceipt.lock_guid!(travel_guid)
      lock!
      next unless completed_at_tick.present? && !is_paused
      # Retain identity before deleting already-completed historical evidence.
      TravelRequestReceipt.finish!(self,'completed',completed_at_tick)
      # Completed historical evidence must not release a newer pending journey.
      destroy_for_lifecycle!(reason:'stale_completed',current_tick:current_tick)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def destroy_for_lifecycle!(reason:, current_tick: Tick.current, ship_status: nil)
    return if destroyed?

    if ship_status.present? && user_ship.status.to_s.downcase == "in_transit"
      user_ship.update!(status: ship_status)
    end

    Rails.logger.info(
      "event=ship_travel_destroyed reason=#{reason} ship_travel_id=#{id} " \
        "user_ship_id=#{user_ship_id} travel_guid=#{travel_guid} " \
        "arrival_tick=#{arrival_tick} completed_at_tick=#{completed_at_tick.inspect} " \
        "current_tick=#{current_tick}"
    )

    destroy!
  end

  private

  def normalize_rabbitmq_environment
    normalized = RabbitmqConnection.normalize(rabbitmq_environment)
    self.rabbitmq_environment = normalized.presence || RabbitmqConnection::DEFAULT_ENVIRONMENT
  end
end
