# app/models/production_facility.rb

class ProductionFacility < ApplicationRecord
  belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true
  belongs_to :commodity

  validates :facility_name, :production_rate, :consumption_rate, presence: true

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
end
