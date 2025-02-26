class UserShip < ApplicationRecord
    belongs_to :user
    belongs_to :ship
    has_many :user_ship_cargos
  
    validates :total_scu, :used_scu, presence: true
  
    # Calculate remaining cargo space
    def available_cargo_space
      total_scu - used_scu
    end
  end
  