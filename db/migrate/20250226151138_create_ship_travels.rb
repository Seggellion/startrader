class CreateShipTravels < ActiveRecord::Migration[8.0]
  def change
    create_table :ship_travels do |t|
      t.references :user_ship, null: false, foreign_key: true
      t.references :from_location, null: false, foreign_key: { to_table: :locations }
      t.references :to_location, null: false, foreign_key: { to_table: :locations }
      t.integer :departure_tick, null: false
      t.integer :arrival_tick, null: false

      t.timestamps
    end

    
    change_table :ships, bulk: true do |t|
      t.string :name
      t.float :width
      t.float :fuel_quantum
      t.float :fuel_hydrogen
    end

        # 6) TICKS
        create_table :ticks do |t|
          t.integer  :sequence
          t.integer  :current_tick
          t.datetime :processed_at
    
          t.timestamps
        end
    add_column :user_ships, :location_name, :string

    # Ensure the column is indexed for quick lookup
    add_index :user_ships, :location_name

    # Make sure Location names are unique for this association to work
    add_index :locations, :name, unique: true

    remove_foreign_key :locations, column: :parent_id, if_exists: true

    # Rename the existing column to `parent_name`
    rename_column :locations, :parent_id, :parent_name

    # Change the column type to string
    change_column :locations, :parent_name, :string

    # Update the index for the new column
    remove_index :locations, :parent_name, if_exists: true
    add_index :locations, :parent_name


  end
end
