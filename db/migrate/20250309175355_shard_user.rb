class ShardUser < ActiveRecord::Migration[8.0]
  def change
    add_column :shard_users, :shard_name, :string
    add_column :user_ship_cargos, :commodity_name, :string
    add_column :star_bitizen_runs, :commodity_name, :string
    add_column :star_bitizen_runs, :shard, :string
    add_column :star_bitizen_runs, :buy_location_name, :string
    add_column :star_bitizen_runs, :sell_location_name, :string
    rename_column :user_ships, :host_twitch_id, :shard_name
    add_column :star_bitizen_runs, :local_buy_price, :integer
    add_column :star_bitizen_runs, :user_ship_id, :integer
    add_column  :star_bitizen_runs, :local_sell_price, :integer
    add_column :shard_users, :wallet_balance, :integer, default: 0
  end
end
