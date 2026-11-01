require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class TravelConstraintsTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup { setup_travel_repair }
  def rejected_sql(sql)
    assert_raises(ActiveRecord::StatementInvalid) do
      ShipTravel.transaction(requires_new:true){ActiveRecord::Base.connection.execute(sql)}
    end
  end
  test 'SQL bypass accepts coherent zero and positive legacy pause and rejects invalid states without UNKNOWN loopholes' do
    t=saved_trip
    c=ActiveRecord::Base.connection
    rejected_sql("UPDATE ship_travels SET arrival_tick=0 WHERE id=#{t.id}")
    rejected_sql("UPDATE ship_travels SET arrival_tick=-1 WHERE id=#{t.id}")
    rejected_sql("UPDATE ship_travels SET arrival_tick=NULL WHERE id=#{t.id}")
    base="arrival_tick=0,is_paused=true,paused_at_tick=95,remaining_ticks_from_arrival=5,interdiction_count=1,last_interdicted_tick=95"
    c.execute("UPDATE ship_travels SET #{base} WHERE id=#{t.id}")
    assert_equal 'interdicted',TravelState.new(t.reload).state
    ['paused_at_tick=NULL','remaining_ticks_from_arrival=NULL','remaining_ticks_from_arrival=-1',
     'last_interdicted_tick=NULL','last_interdicted_tick=94','interdiction_count=0','completed_at_tick=100'].each do |bad|
      rejected_sql("UPDATE ship_travels SET #{bad} WHERE id=#{t.id}")
    end
    c.execute("UPDATE ship_travels SET arrival_tick=100 WHERE id=#{t.id}")
    assert_equal 'interdicted',TravelState.new(t.reload).state
    duplicate=t.attributes.except('id','created_at','updated_at').merge('travel_guid'=>'second')
    assert_raises(ActiveRecord::RecordNotUnique) do
      ShipTravel.transaction(requires_new:true){ShipTravel.insert_all!([duplicate])}
    end
    assert_equal 1,ShipTravel.count
  end
end
