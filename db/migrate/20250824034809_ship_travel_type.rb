class ShipTravelType < ActiveRecord::Migration[8.0]
  def change


    add_column :locations, :has_trade_terminal, :boolean
    add_column :ship_travels, :ship_travel_type, :string
  end
end
