class GuardUnfinishedShipJourneys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  NAME='index_one_unfinished_journey_per_ship'
  def up
    if select_value("SELECT 1 FROM ship_travels WHERE completed_at_tick IS NULL GROUP BY user_ship_id HAVING count(*) > 1 LIMIT 1")
      raise 'Duplicate unfinished journeys require a reviewed disposition; no rows were changed.'
    end
    index=select_one("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.relname='#{NAME}'")
    raise 'Existing invalid journey index: review then DROP INDEX CONCURRENTLY before retry.' if index && !index['indisvalid']
    add_index :ship_travels,:user_ship_id,unique:true,where:'completed_at_tick IS NULL',name:NAME,algorithm: :concurrently unless index
  end
  def down
    remove_index :ship_travels,name:NAME,algorithm: :concurrently,if_exists:true
  end
end
