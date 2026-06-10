class UpdateShipTravelsForeignKeysToCascade < ActiveRecord::Migration[8.0]
  def change
      def up
    # Remove existing strict foreign keys
    remove_foreign_key :ship_travels, :locations, column: :from_location_id
    remove_foreign_key :ship_travels, :locations, column: :to_location_id

    # Add cascading foreign keys
    add_foreign_key :ship_travels, :locations, column: :from_location_id, on_delete: :cascade
    add_foreign_key :ship_travels, :locations, column: :to_location_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :ship_travels, :locations, column: :from_location_id
    remove_foreign_key :ship_travels, :locations, column: :to_location_id

    add_foreign_key :ship_travels, :locations, column: :from_location_id
    add_foreign_key :ship_travels, :locations, column: :to_location_id
  end
  end
end
