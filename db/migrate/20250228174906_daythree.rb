class Daythree < ActiveRecord::Migration[8.0]
  def change
    remove_column :terminals, :location_id, :bigint
    add_column :terminals, :location_name, :string

    # Optionally add an index for faster lookups
    add_index :terminals, :location_name
        # Remove the old location_id column
        remove_column :production_facilities, :location_id, :bigint

        # Add the new location_name column
        add_column :production_facilities, :location_name, :string
    
        # Optional: Add an index for faster lookups by location_name
        add_index :production_facilities, :location_name

        add_column :users, :wallet_balance, :decimal, default: 0.0, precision: 15, scale: 2
        add_column :user_ships, :status, :string, default: 'docked', null: false

  end
end
