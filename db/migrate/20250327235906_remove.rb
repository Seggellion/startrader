class Remove < ActiveRecord::Migration[8.0]
  def change
    remove_column :production_facilities, :commodity_id
  end
end
