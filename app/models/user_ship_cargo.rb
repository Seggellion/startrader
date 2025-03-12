class UserShipCargo < ApplicationRecord
    belongs_to :user_ship
    belongs_to :commodity

    has_many :star_bitizen_runs, foreign_key: :user_ship_cargo_id

  before_destroy :nullify_star_bitizen_runs
  
    validates :scu, numericality: { greater_than_or_equal_to: 0 }
  
    # Calculate potential profit
    def potential_profit
      (sell_price - buy_price) * scu
    end

    private

    def nullify_star_bitizen_runs
      star_bitizen_runs.update_all(user_ship_cargo_id: nil)
    end
  
  end
  