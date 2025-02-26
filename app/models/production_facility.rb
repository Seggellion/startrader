class ProductionFacility < ApplicationRecord
    belongs_to :location
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
  