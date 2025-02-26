class Commodity < ApplicationRecord
    has_many :production_facilities
    has_many :location_commodities, through: :production_facilities
  
    validates :name, presence: true
  
    # Example method to calculate dynamic price (e.g., based on supply/demand)
    def dynamic_price
      current_price # You can expand this with a pricing algorithm
    end
  end
  