class Ship < ApplicationRecord
    has_many :user_ships, dependent: :destroy
    has_many :users, through: :user_ships
  
    validates :model, presence: true, uniqueness: true
  
    # Example method to calculate cargo capacity
    def available_cargo_capacity(used_scu)
      scu - used_scu
    end
  end
  