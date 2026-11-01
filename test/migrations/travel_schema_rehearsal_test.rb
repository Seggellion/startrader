require 'test_helper'
require_relative '../support/travel_repair_fixtures'
require_relative '../../db/migrate/20261101010100_guard_travel_arrival_state'
require_relative '../../db/migrate/20261101010200_guard_unfinished_ship_journeys'
require_relative '../../db/migrate/20261101010300_validate_travel_arrival_state'
class TravelSchemaRehearsalTest < ActiveSupport::TestCase
  self.use_transactional_tests=false
  include TravelRepairFixtures
  setup { setup_travel_repair }
  teardown { cleanup_travel_repair }

  def transactional_migrate(migration,direction)
    ActiveRecord::Base.transaction { migration.migrate(direction) }
  end

  test 'NOT VALID protects new writes preserves legacy evidence and validates without rewriting valid interdictions' do
    t=saved_trip
    c=ActiveRecord::Base.connection
    transactional_migrate(GuardTravelArrivalState.new,:down)
    t.update_columns(arrival_tick:0)
    transactional_migrate(GuardTravelArrivalState.new,:up)
    assert_equal 0,t.reload.arrival_tick
    assert_raises(ActiveRecord::StatementInvalid){t.update_columns(arrival_tick:0)}
    assert_raises(ActiveRecord::StatementInvalid){transactional_migrate(ValidateTravelArrivalState.new,:up)}
    t.update_columns(arrival_tick:100)
    t.interdict!(95)
    before=t.reload.attributes
    transactional_migrate(ValidateTravelArrivalState.new,:up)
    assert_equal before,t.reload.attributes
    t.update_columns(arrival_tick:100)
    assert t.reload.is_paused?
  ensure
    ShipTravel.delete_all
    transactional_migrate(ValidateTravelArrivalState.new,:up)
  end

  test 'concurrent index refuses duplicates leaves evidence and recovers an invalid build only after explicit cleanup' do
    t=saved_trip
    c=ActiveRecord::Base.connection
    migration=GuardUnfinishedShipJourneys.new
    migration.migrate(:down)
    duplicate=ShipTravel.insert_all!([t.attributes.except('id').merge('travel_guid'=>'synthetic-duplicate')]).rows.first.first
    assert_raises(StandardError){migration.migrate(:up)}
    assert_equal 2,ShipTravel.count
    assert_raises(ActiveRecord::StatementInvalid) do
      c.execute('CREATE UNIQUE INDEX CONCURRENTLY index_one_unfinished_journey_per_ship ON ship_travels(user_ship_id) WHERE completed_at_tick IS NULL')
    end
    assert_equal false,c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid='index_one_unfinished_journey_per_ship'::regclass")
    # Explicit synthetic fixture disposition, not an application repair algorithm.
    ShipTravel.where(id:duplicate).delete_all
    error=assert_raises(StandardError){migration.migrate(:up)}
    assert_includes error.message,'invalid journey index'
    migration.migrate(:down)
    migration.migrate(:up)
    assert ShipTravel.exists?(t.id)
    assert_equal true,c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid='index_one_unfinished_journey_per_ship'::regclass")
  ensure
    ShipTravel.delete_all
    migration&.migrate(:down)
    migration&.migrate(:up)
  end
end
