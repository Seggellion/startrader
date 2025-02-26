class PriceHistory < ApplicationRecord
    belongs_to :city_commodity
  
    validates :price, numericality: { greater_than_or_equal_to: 0 }
    validates :recorded_at, presence: true
  end
  