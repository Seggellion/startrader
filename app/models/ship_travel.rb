# app/models/ship_travel.rb
class ShipTravel < ApplicationRecord
  belongs_to :user_ship
  belongs_to :from_location, class_name: 'Location'
  belongs_to :to_location,   class_name: 'Location'

  # "Active" means in-flight and not paused
  scope :active, -> {
    where(is_paused: false).where('arrival_tick >= ?', Tick.current)
  }

  scope :in_flight_now, ->(tick = Tick.current) {
    where(is_paused: false)
      .where('departure_tick <= ? AND arrival_tick >= ?', tick, tick)
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
    total_duration_ticks.positive? ? total_duration_ticks : (arrival_tick - departure_tick)
  end

  def window_ticks
    ((duration_ticks * interdict_window_percent) / 100.0).ceil
  end

  def seconds_remaining(current_tick)
    [arrival_tick - current_tick, 0].max * Tick::SECONDS_PER_TICK
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
    return nil if is_paused
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

  # --- Interdiction controls ---

  # Pauses travel and records remaining distance to arrival.
  # Idempotent: calling when already paused simply returns self.
  def interdict!(current_tick = Tick.current)
    return self if is_paused

    update!(
      is_paused: true,
      paused_at_tick: current_tick,
      remaining_ticks_from_arrival: distance_from_arrival_in_ticks(current_tick),
      interdiction_count: interdiction_count + 1,
      last_interdicted_tick: current_tick,
      arrival_tick: 0
    )
  end

  # Resumes travel from the recorded remaining ticks.
  # Sets a fresh departure/arrival so downstream logic stays simple.
  def resume!(current_tick = Tick.current)
    
    raise "Not paused" unless is_paused
    rem = remaining_ticks_from_arrival.to_i
    rem = 1 if rem <= 0 


    update!(
      is_paused: false,
      paused_at_tick: nil,
      departure_tick: current_tick,
      arrival_tick: current_tick + rem,
      total_duration_ticks: rem # the remaining leg is now the new trip duration
    )
  end
end
