# app/models/tick.rb
class Tick < ApplicationRecord
  validates :current_tick, presence: true, numericality: { only_integer: true }
  validates :sequence, presence: true, numericality: { only_integer: true }

  after_save :update_market_prices, if: :saved_change_to_current_tick?

 SECONDS_PER_TICK = Setting.get('seconds_per_tick').to_i

 SIMULATED_HOURS_PER_TICK  = Setting.get('hours_per_tick').to_i * 3600

 
  def self.seconds_per_tick = SECONDS_PER_TICK
    def self.hours_per_tick = SIMULATED_HOURS_PER_TICK

  def self.current
    first_or_create(current_tick: 0, sequence: 1).current_tick
  end

  def self.current_sequence
    instance.sequence
  end
  # Get the current tick instance (for accessing both current_tick and sequence)
  def self.instance
    first_or_create(current_tick: 0, sequence: 1)
  end

  def self.increment!
    
    tick = first_or_create(current_tick: 0, sequence: 1)
    ShipArrivalJob.perform_later
    tick.update!(current_tick: tick.current_tick + 1, sequence: tick.sequence + 1)
    tick.process_tick # Runs optimized processing logic
    tick.send(:correct_ship_statuses) if tick.current_tick % 3 == 0
  ActionCable.server.broadcast("tick", {
    type: "tick",
    tick: Tick.current,
    seconds_per_tick: Tick::SIMULATED_HOURS_PER_TICK
  })
  end

  def process_tick
    # ✅ Process production/consumption in bulk
    batch_produce_resources
    batch_consume_resources
    update!(processed_at: Time.current)
  end

  private

  def batch_produce_resources
    # Generate commodities only for facilities that haven't hit `max_inventory`
    facilities = ProductionFacility.where("inventory < max_inventory")

    updates = facilities.map do |facility|
      new_inventory = [facility.inventory + facility.production_rate, facility.max_inventory].min
      "(#{facility.id}, #{new_inventory})"
    end

    # Bulk update inventories
    unless updates.empty?
      sql = <<-SQL
        UPDATE production_facilities
        SET inventory = data.new_inventory
        FROM (VALUES #{updates.join(",")}) AS data(id, new_inventory)
        WHERE production_facilities.id = data.id
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end
  end

  def batch_consume_resources
    # Consume resources in bulk using a similar approach
    facilities = ProductionFacility.where("inventory > 0")

    updates = facilities.map do |facility|
      new_inventory = [facility.inventory - facility.consumption_rate, 0].max
      "(#{facility.id}, #{new_inventory})"
    end

    unless updates.empty?
      sql = <<-SQL
        UPDATE production_facilities
        SET inventory = data.new_inventory
        FROM (VALUES #{updates.join(",")}) AS data(id, new_inventory)
        WHERE production_facilities.id = data.id
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end
  end

  def correct_ship_statuses
    ActiveRecord::Base.connection.execute(<<-SQL)
      UPDATE user_ships
      SET status = 'aimlessly floating in space'
      WHERE status = 'in_transit'
      AND id NOT IN (SELECT user_ship_id FROM ship_travels WHERE arrival_tick > #{Tick.current})
    SQL
  end
  

  def update_market_prices    
    MarketPriceUpdater.update_prices! if current_tick % 1 == 0
  end
end
