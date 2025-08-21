class ShipSlug < ActiveRecord::Migration[8.0]
  def change
        add_column :shards, :channel_uuid, :string
        add_column :user_ships, :ship_slug, :string
        add_column :user_ships, :guid, :string
        add_column :user_ships, :shard_id, :integer
            add_index :user_ships, :shard_id

    create_table :tick_controls do |t|
      t.boolean :running, null: false, default: false
      t.timestamps
    end

    change_table :ship_travels do |t|
      t.integer :total_duration_ticks, null: false, default: 0 
      t.boolean :is_paused, null: false, default: false  
      t.integer :paused_at_tick
      t.integer :remaining_ticks_from_arrival
      t.integer :interdict_window_percent, null: false, default: 15
      t.integer :interdiction_count, null: false, default: 0
      t.integer :last_interdicted_tick
    end
    add_index :ship_travels, [:is_paused, :departure_tick, :arrival_tick]

        add_reference :user_ships, :shard_user, foreign_key: true, index: true
    # if not already present as a real FK:
    add_foreign_key :user_ships, :shards, column: :shard_id
    add_index :user_ships, :guid, unique: true

  end
end
