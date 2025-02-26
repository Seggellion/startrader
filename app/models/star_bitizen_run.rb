class StarBitizenRun < ApplicationRecord
    belongs_to :user
    belongs_to :user_ship_cargo, optional: true
    belongs_to :buy_location, class_name: 'Location'
    belongs_to :sell_location, class_name: 'Location'
  
    validates :profit, :scu, numericality: { greater_than_or_equal_to: 0 }
  
    # Calculate distance dynamically based on orbital mechanics
    def distance
      # Placeholder for orbital distance calculation logic
      Math.sqrt((buy_location.periapsis - sell_location.periapsis)**2)
    end
  end
  