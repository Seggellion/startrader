# app/models/production_facility.rb

class ProductionFacility < ApplicationRecord
  include ActionView::RecordIdentifier

  belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true

  # Using `commodity_name` instead of `commodity_id`
  belongs_to :commodity, 
             primary_key: :name, 
             foreign_key: :commodity_name

  validates :facility_name, :production_rate, :consumption_rate, presence: true

  after_update_commit :broadcast_market_row, if: :market_values_changed?

  # Generate resources on game ticks
  def produce    
    self.inventory = [inventory + production_rate, max_inventory].min
    save!
  end

  # Consume resources during gameplay (e.g., population or ship requirements)
  def consume
    self.inventory = [inventory - consumption_rate, 0].max
    save!
  end

  def broadcast_market_row
    broadcast_replace_later_to(
      "market_prices",
      target: dom_id(self, :market_row),
      partial: "star_trader/market_row",
      locals: { facility: self }
    )
  end

  private

  def market_values_changed?
    (previous_changes.keys & %w[
      inventory
      max_inventory
      local_buy_price
      local_sell_price
      price_buy
      price_sell
      scu_buy
      scu_sell
      scu_sell_stock
      status_buy
      status_sell
      updated_at
    ]).any?
  end
end
