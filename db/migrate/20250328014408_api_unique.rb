class ApiUnique < ActiveRecord::Migration[8.0]
  def change
    remove_index :production_facilities, :api_id

    add_index :production_facilities, :api_id, unique: true
  end
end
