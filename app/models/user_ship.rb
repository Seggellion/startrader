class UserShip < ApplicationRecord
    belongs_to :user
    belongs_to :ship
    has_many :user_ship_cargos
    belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true

    validates :total_scu, :used_scu, presence: true


  has_one :active_travel, -> { where('arrival_tick > ?', Tick.current) }, class_name: 'ShipTravel'

    # Calculate remaining cargo space
    def available_cargo_space
      total_scu - used_scu
    end


  # Add cargo to the ship's used SCU
  def add_cargo_scu(scu)
    new_used_scu = [used_scu.to_i + scu.to_i, total_scu.to_i].min
    update!(used_scu: new_used_scu)
  end

  # Remove cargo from the ship's used SCU
  def remove_cargo_scu(scu)
    new_used_scu = [used_scu.to_i - scu.to_i, 0].max
    update!(used_scu: new_used_scu)
  end


  end
  