class WidenTradeCurrencyColumns < ActiveRecord::Migration[8.0]
  def up
    change_column :shard_users, :wallet_balance, :bigint, default: 0
    change_column :star_bitizen_runs, :profit, :bigint, default: 0

    change_column :star_bitizen_runs, :local_buy_price, :decimal, precision: 15, scale: 2
    change_column :star_bitizen_runs, :local_sell_price, :decimal, precision: 15, scale: 2
  end

  def down
    change_column :star_bitizen_runs, :local_sell_price, :integer
    change_column :star_bitizen_runs, :local_buy_price, :integer

    change_column :star_bitizen_runs, :profit, :integer, default: 0
    change_column :shard_users, :wallet_balance, :integer, default: 0
  end
end
