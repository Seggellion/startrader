class UserShipCargo < ApplicationRecord
    belongs_to :user_ship
    belongs_to :commodity
  
    validates :scu, numericality: { greater_than_or_equal_to: 0 }
  
    # Calculate potential profit
    def potential_profit
      (sell_price - buy_price) * scu
    end
  end
  