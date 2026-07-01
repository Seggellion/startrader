# app/models/tick.rb
class Tick < ApplicationRecord
  validates :current_tick, presence: true, numericality: { only_integer: true }
  validates :sequence, presence: true, numericality: { only_integer: true }

  after_save :update_market_prices, if: :saved_change_to_current_tick?

  DEFAULT_SECONDS_PER_TICK = 1
  DEFAULT_HOURS_PER_TICK = 1

  def self.seconds_per_tick
    positive_number_setting("seconds_per_tick", DEFAULT_SECONDS_PER_TICK)
  end

  def self.simulated_seconds_per_tick
    positive_number_setting("hours_per_tick", DEFAULT_HOURS_PER_TICK) * 3600
  end

  # Existing callers expect this value in seconds, despite the method name.
  def self.hours_per_tick = simulated_seconds_per_tick

  def self.current
    instance.current_tick
  end

  def self.current_sequence
    instance.sequence
  end
  # Get the current tick instance (for accessing both current_tick and sequence)
  def self.instance
    first_or_create(current_tick: 0, sequence: 1)
  end

  def self.increment!
    tick = nil

    transaction do
      tick = instance
      tick.with_lock do
        tick.update!(
          current_tick: tick.current_tick.to_i + 1,
          sequence: tick.sequence.to_i + 1
        )
        tick.process_tick
      end
    end

    run_tick_side_effect("ShipArrivalJob") { ShipArrivalJob.perform_now }
    run_tick_side_effect("ShipTravel.cleanup_stale_after_arrival!") do
      ShipTravel.cleanup_stale_after_arrival!(tick.current_tick)
    end
    run_tick_side_effect("Tick.correct_ship_statuses") { tick.send(:correct_ship_statuses) } if tick.current_tick % 3 == 0
    broadcast_tick(tick.current_tick)

    tick.current_tick
  end

  def process_tick
    batch_produce_resources
    batch_consume_resources
    update!(processed_at: Time.current)
  end

  private

  def batch_produce_resources
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE production_facilities
      SET inventory = LEAST(
        COALESCE(inventory, 0) + COALESCE(production_rate, 0),
        COALESCE(max_inventory, 0)
      )
      WHERE COALESCE(inventory, 0) < COALESCE(max_inventory, 0)
    SQL
  end

  def batch_consume_resources
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE production_facilities
      SET inventory = GREATEST(
        COALESCE(inventory, 0) - COALESCE(consumption_rate, 0),
        0
      )
      WHERE COALESCE(inventory, 0) > 0
    SQL
  end

  def correct_ship_statuses
    current_tick = Tick.current.to_i
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE user_ships
      SET status = 'aimlessly floating in space'
      WHERE status = 'in_transit'
      AND NOT EXISTS (
        SELECT 1
        FROM ship_travels
        WHERE ship_travels.user_ship_id = user_ships.id
        AND (
          ship_travels.is_paused = TRUE
          OR (
            ship_travels.completed_at_tick IS NULL
            AND ship_travels.arrival_tick > #{current_tick}
          )
        )
      )
    SQL
  end


  def update_market_prices
    self.class.run_tick_side_effect("MarketPriceUpdater") do
      MarketPriceUpdater.update_prices! if current_tick % 1 == 0
    end
  end

  def self.broadcast_tick(current_tick)
    run_tick_side_effect("ActionCable.tick_broadcast") do
      ActionCable.server.broadcast("tick", {
        type: "tick",
        tick: current_tick,
        seconds_per_tick: Tick.seconds_per_tick
      })
    end
  end

  def self.run_tick_side_effect(name)
    yield
  rescue => error
    Rails.logger.error(
      "event=\"tick_side_effect_failed\" side_effect=#{name.inspect} " \
        "error_class=#{error.class.name.inspect} error_message=#{error.message.inspect}"
    )
    nil
  end

  def self.positive_number_setting(key, fallback)
    raw_value = Setting.get(key)
    value = Float(raw_value)
    return fallback if value <= 0

    value.to_i == value ? value.to_i : value
  rescue ArgumentError, TypeError
    fallback
  end
  private_class_method :positive_number_setting
end
