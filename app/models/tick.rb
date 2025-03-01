# app/models/tick.rb

class Tick < ApplicationRecord
  validates :current_tick, presence: true, numericality: { only_integer: true }
  validates :sequence, presence: true, numericality: { only_integer: true }

  after_save :update_market_prices, if: :saved_change_to_current_tick?

  def self.current
    first_or_create(current_tick: 0, sequence: 1).current_tick
  end

  # Set the current tick manually (for testing or game logic)
  def self.set_current(tick_number)
    tick = first_or_create(current_tick: 0, sequence: 1)
    ShipArrivalJob.perform_later
    tick.update!(current_tick: tick_number, sequence: tick.sequence + 1)
  end

  # Get the current tick instance (for accessing both current_tick and sequence)
  def self.instance
    first_or_create(current_tick: 0, sequence: 1)
  end

  # Increment the tick (for automated or manual advancement)
  def self.increment!
    tick = first_or_create(current_tick: 0, sequence: 1)
   # ShipArrivalJob.perform_later
    tick.update!(current_tick: tick.current_tick + 1, sequence: tick.sequence + 1)
  end

  def self.current_sequence
    instance.sequence
  end

  # Example method to process a game tick
  def process_tick
    ProductionFacility.find_each(&:produce)
    ProductionFacility.find_each(&:consume)
    update!(processed_at: Time.current)
  end

  private

  def update_market_prices

    if current_tick % 1 == 0

      MarketPriceUpdater.update_prices!
    end

  end
end
