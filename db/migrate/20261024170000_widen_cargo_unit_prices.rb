class WidenCargoUnitPrices < ActiveRecord::Migration[8.0]
  def up
    change_column :user_ship_cargos, :buy_price, :decimal, precision: 15, scale: 2
    change_column :user_ship_cargos, :sell_price, :decimal, precision: 15, scale: 2
  end

  def down
    # Narrowing must never silently round/truncate prices accepted by the new schema.
    too_large = select_value(<<~SQL)
      SELECT 1 FROM user_ship_cargos
      WHERE ABS(buy_price) >= 100000000 OR ABS(sell_price) >= 100000000
      LIMIT 1
    SQL
    raise ActiveRecord::IrreversibleMigration, "Cargo prices exceed the previous precision" if too_large

    change_column :user_ship_cargos, :buy_price, :decimal, precision: 10, scale: 2
    change_column :user_ship_cargos, :sell_price, :decimal, precision: 10, scale: 2
  end
end
