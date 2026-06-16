require "securerandom"

class AddTravelGuidToShipTravels < ActiveRecord::Migration[8.0]
  def up
    add_column :ship_travels, :travel_guid, :string
    add_column :ship_travels, :completed_at_tick, :integer

    say_with_time "Backfilling ship_travels.travel_guid" do
      select_values("SELECT id FROM ship_travels WHERE travel_guid IS NULL OR travel_guid = ''").each do |id|
        execute <<~SQL.squish
          UPDATE ship_travels
          SET travel_guid = #{quote("legacy-#{id}-#{SecureRandom.uuid}")}
          WHERE id = #{id.to_i}
        SQL
      end
    end

    change_column_null :ship_travels, :travel_guid, false
    add_index :ship_travels, :travel_guid, unique: true
    add_index :ship_travels, :completed_at_tick
  end

  def down
    remove_index :ship_travels, :completed_at_tick
    remove_index :ship_travels, :travel_guid
    remove_column :ship_travels, :completed_at_tick
    remove_column :ship_travels, :travel_guid
  end
end
