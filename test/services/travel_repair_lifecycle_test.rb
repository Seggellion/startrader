require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class TravelRepairLifecycleTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup { setup_travel_repair }
  def complete(travel, tick:travel.arrival_tick)
    ShipTravelArrivalProcessor.new(travel:travel,current_tick:tick).call
  end

  test 'remote gateway aligns initialized player and supports next jump' do
    before=assets
    travel=gate_start
    assert_equal @gate.name,@hull.reload.location_name
    assert_equal @gate.name,@player.reload.current_location_name
    complete(travel)
    assert_equal @destination.name,@player.reload.current_location_name
    result=GateTravelService.new(ship_guid:@hull.guid,travel_guid:'return',gateway_name:'Repair A Gateway').call
    assert_equal @gate,result.arrival_location
    assert_equal before,assets
  end

  test 'preexisting mismatch rejects remote gateway without any state writes' do
    @player.update_current_location!(@destination)
    before=[@hull.reload.attributes,@player.reload.attributes]
    e=assert_raises(TravelLifecycle::Error){gate_start}
    assert_equal 'location_mismatch',e.code
    assert_equal before,[@hull.reload.attributes,@player.reload.attributes]
    assert_empty ShipTravel.all
    assert_empty TravelRequestReceipt.all
  end

  test 'lazy completion refreshes player and departs in same request' do
    travel=gate_start
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:109)
    result=GateTravelService.new(ship_guid:@hull.guid,travel_guid:'lazy-return',gateway_name:'Repair A Gateway').call
    assert_equal @destination,result.origin_location
    assert_equal @destination.name,@player.reload.current_location_name
    assert_equal 1,ShipTravel.count
    assert_equal 'completed',TravelRequestReceipt.find_by!(travel_guid:travel.travel_guid).outcome
  end

  test 'arrival preserves player legitimately elsewhere' do
    travel=gate_start
    @player.reload.update_current_location!(@origin)
    complete(travel)
    assert_equal @origin.name,@player.reload.current_location_name
    e=assert_raises(TravelLifecycle::Error){GateTravelService.new(ship_guid:@hull.guid).call}
    assert_equal 'location_mismatch',e.code
    assert_equal @destination.name,@hull.reload.location_name
  end

  test 'interdiction remains across reload long ticks and repeated pause and gives actionable rejection' do
    travel=gate_start
    travel.interdict!(100,enforce_window:true)
    snapshot=travel.reload.attributes
    travel.interdict!(10000)
    assert_equal snapshot,travel.reload.attributes
    assert_equal 'interdicted',@hull.reload.status
    assert_equal 'interdicted',TravelState.new(travel,tick:10000).state
    Tick.instance.update_columns(current_tick:10000)
    ShipArrivalJob.perform_now
    assert ShipTravel.exists?(travel.id)
    e=assert_raises(TravelLifecycle::Error){gate_start}
    assert_equal 'interdicted',e.code
    assert_includes e.message,'resume'
    assert_equal 0,travel.reload.arrival_tick
  end

  test 'resume positive zero missing and negative saved remainder' do
    travel=gate_start
    travel.interdict!(100)
    travel.resume!(200)
    assert_equal 208,travel.reload.arrival_tick
    travel.interdict!(200)
    travel.update!(remaining_ticks_from_arrival:0)
    travel.resume!(300)
    assert_equal 301,travel.reload.arrival_tick
    assert_equal 'in_transit',@hull.reload.status
    travel.interdict!(300)
    connection=ActiveRecord::Base.connection
    connection.execute('ALTER TABLE ship_travels DROP CONSTRAINT ship_travels_arrival_state')
    [nil,-1].each do |value|
      travel.update_columns(remaining_ticks_from_arrival:value)
      before=[travel.reload.attributes,@hull.reload.attributes]
      assert_raises(TravelLifecycle::Error){travel.resume!(400)}
      assert_equal before,[travel.reload.attributes,@hull.reload.attributes]
    end
  end

  test 'invalid unpaused zero blocks even when existing legacy row bypassed guards' do
    travel=gate_start
    ActiveRecord::Base.connection.execute('ALTER TABLE ship_travels DROP CONSTRAINT ship_travels_arrival_state')
    travel.update_columns(arrival_tick:0)
    e=assert_raises(TravelLifecycle::Error){gate_start}
    assert_equal 'invalid_state',e.code
    assert_equal 1,ShipTravel.count
    assert_equal 'invalid',TravelState.new(travel).state
    ShipArrivalJob.perform_now
    assert ShipTravel.exists?(travel.id)
  end

  test 'gateway ship save failure rolls back journey receipt and player relocation' do
    before=assets
    callback=-> { raise 'injected save failure' if status=='in_transit' }
    UserShip.set_callback(:update,:before,callback)
    assert_raises(RuntimeError){gate_start}
    assert_empty ShipTravel.all
    assert_empty TravelRequestReceipt.all
    assert_equal @origin.name,@player.reload.current_location_name
    assert_equal @origin.name,@hull.reload.location_name
    assert_equal before,assets
  ensure
    UserShip.skip_callback(:update,:before,callback)
  end

  test 'interdiction and resume rollback travel when ship save fails' do
    travel=gate_start
    callback=-> { raise 'injected state failure' }
    UserShip.set_callback(:update,:before,callback)
    assert_raises(RuntimeError){travel.interdict!(100)}
    assert_not travel.reload.is_paused?
    assert_equal 108,travel.arrival_tick
    UserShip.skip_callback(:update,:before,callback)
    travel.interdict!(100)
    UserShip.set_callback(:update,:before,callback)
    assert_raises(RuntimeError){travel.resume!(200)}
    assert travel.reload.is_paused?
    assert_equal 0,travel.arrival_tick
  ensure
    UserShip.skip_callback(:update,:before,callback,raise:false)
  end

  test 'same request replay survives completion and conflicting reuse never starts again' do
    travel=gate_start('replay-key')
    assert gate_start('replay-key').request_replayed
    assert_equal 1,ShipTravel.count
    complete(travel)
    replay=gate_start('replay-key')
    assert replay.request_replayed
    assert_equal 'completed',replay.request_outcome
    assert_empty ShipTravel.all
    assert_equal 1,TravelArrivalEvent.count
    e=assert_raises(TravelLifecycle::Error) do
      GateTravelService.new(ship_guid:@hull.guid,gateway_name:'wrong',travel_guid:'replay-key').call
    end
    assert_equal 'request_conflict',e.code
  end

  test 'completion rolls back fully before commit and outbox sweep recovers lost enqueue' do
    travel=gate_start
    original=[@hull.reload.location_name,@player.reload.current_location_name]
    TravelArrivalEvent.stub(:create!,->(**_){raise 'injected before commit'}) do
      assert_raises(RuntimeError){complete(travel)}
    end
    assert ShipTravel.exists?(travel.id)
    assert_equal original,[@hull.reload.location_name,@player.reload.current_location_name]
    assert_equal 'pending',TravelRequestReceipt.find_by!(travel_guid:travel.travel_guid).outcome
    complete(travel.reload)
    assert_empty ShipTravel.all
    # No queue execution is needed: independent sweep rediscovers the committed row.
    sent=[]
    RabbitmqSender.stub(:send_arrival_event,->(e){sent << [e.event_guid,e.rabbitmq_environment]}) do
      TravelArrivalDispatchJob.perform_now
      TravelArrivalDispatchJob.perform_now
    end
    assert_equal 1,sent.size
    assert_equal 'prod',sent.first.last
  end

  test 'uncertain send retains event identity and retry never redoes authoritative arrival' do
    travel=gate_start
    complete(travel)
    event=TravelArrivalEvent.sole
    sends=[]
    RabbitmqSender.stub(:send_arrival_event,->(e){sends << e.event_guid;raise IOError,'after send before confirmation'}){event.deliver!}
    assert_nil event.reload.sent_at
    assert_equal 1,event.attempts
    event.update!(next_attempt_at:nil)
    RabbitmqSender.stub(:send_arrival_event,->(e){sends << e.event_guid}){event.deliver!}
    assert_equal [event.event_guid,event.event_guid],sends
    assert event.reload.sent_at
    assert_equal 1,TravelRequestReceipt.where(outcome:'completed').count
    assert_equal @destination.name,@hull.reload.location_name
    assert_empty ShipTravel.all
  end

  test 'missing reciprocal route rejects with stable category and no writes' do
    @destination.destroy!
    e=assert_raises(TravelLifecycle::Error){gate_start}
    assert_equal 'route_unavailable',e.code
    assert_empty ShipTravel.all
  end
  test 'ordinary departure ship save failure rolls back journey and receipt and preserves assets' do
    before=assets
    callback=-> { raise 'ordinary save failure' if status=='in_transit' }
    UserShip.set_callback(:update,:before,callback)
    calculator=Struct.new(:calculate).new(2)
    TravelTimeCalculator.stub(:new,calculator) do
      assert_raises(RuntimeError) do
        TravelService.new(user_ship:@hull,to_location:@gate,travel_guid:'ordinary-rollback').call
      end
    end
    assert_empty ShipTravel.all
    assert_empty TravelRequestReceipt.all
    assert_equal @origin.name,@hull.reload.location_name
    assert_equal @origin.name,@player.reload.current_location_name
    assert_equal before,assets
  ensure
    UserShip.skip_callback(:update,:before,callback)
  end

  [15,30].each do |seconds|
    test "gateway departure at tick zero uses #{seconds} second ticks" do
      Setting.find_by!(key:'seconds_per_tick').update!(value:seconds.to_s)
      Tick.instance.update_columns(current_tick:0,sequence:1)
      t=gate_start
      assert_equal 0,t.departure_tick
      assert_equal (120.0/seconds).ceil,t.arrival_tick
      assert_equal (120.0/seconds).ceil,t.total_duration_ticks
      assert_equal 120,t.seconds_remaining(0)
    end
  end

  test 'event payload preserves original broker and wire contract without storing secrets' do
    require_relative '../support/fake_rabbitmq'
    t=saved_trip
    complete(t)
    e=TravelArrivalEvent.sole
    refute_includes e.payload.to_json,'repair-secret'
    broker=FakeRabbitmq::ChannelRecorder.new
    RabbitmqConnection.stub(:channel_for,broker.to_proc){e.deliver!}
    assert_equal ['dev'],broker.requested_environments
    publication=broker.publications_for('dev').sole
    fields=publication[:message].split('|')
    assert_equal 14,fields.size
    assert_equal 'repair-secret',fields[10]
    assert_equal t.travel_guid,fields.last
    assert_equal e.event_guid,publication[:message_id]
    assert_equal t.travel_guid,publication[:headers][:travel_guid]
  end

  test 'process death after send rolls back claim and permits stable-identity redelivery' do
    crash=Class.new(Exception)
    t=gate_start
    complete(t)
    e=TravelArrivalEvent.sole
    ids=[]
    RabbitmqSender.stub(:send_arrival_event,->(event){ids << event.event_guid;raise crash}) do
      assert_raises(crash){e.deliver!}
    end
    assert_nil e.reload.sent_at
    assert_equal 0,e.attempts
    RabbitmqSender.stub(:send_arrival_event,->(event){ids << event.event_guid}){e.deliver!}
    assert_equal [e.event_guid,e.event_guid],ids
    assert_equal @destination.name,@hull.reload.location_name
    assert_equal 1,TravelRequestReceipt.where(outcome:'completed').count
  end

  test 'forty paused ticks displays ten nominal minutes after resume not ETA' do
    t=saved_trip(departure_tick:60,arrival_tick:100,total_duration_ticks:40)
    t.interdict!(60)
    payload=TravelState.new(t,tick:100000).payload
    assert_equal 'interdicted',payload[:travel_state]
    assert_equal 600,payload[:nominal_seconds_after_resume]
    assert_equal 'No scheduled arrival while interdicted',payload[:arrival_display]
  end

  test 'confirmation timeout retains retryable delivery without losing completion' do
    require_relative '../support/fake_rabbitmq'
    t=gate_start
    complete(t)
    event=TravelArrivalEvent.sole
    broker=FakeRabbitmq::ChannelRecorder.new
    channel=broker.to_proc.call('prod')
    channel.define_singleton_method(:wait_for_confirms){raise Timeout::Error,'simulated confirmation timeout'}
    RabbitmqConnection.stub(:channel_for,broker.to_proc){event.deliver!}
    assert_equal 'Timeout::Error',event.reload.last_error_class
    assert_nil event.sent_at
    assert event.next_attempt_at
    assert_not channel.open?
    assert_equal 'completed',TravelRequestReceipt.sole.outcome
    assert_equal @destination.name,@hull.reload.location_name
  end

  test 'completed historical cleanup reserves its identity without publishing or repeating completion' do
    t=saved_trip(completed_at_tick:100)
    before=assets
    t.cleanup_stale_after_arrival!(1000)
    assert_empty ShipTravel.all
    receipt=TravelRequestReceipt.sole
    assert_equal t.travel_guid,receipt.travel_guid
    assert_equal 'completed',receipt.outcome
    assert_equal 100,receipt.completed_at_tick
    assert_empty TravelArrivalEvent.all
    error=assert_raises(TravelLifecycle::Error){gate_start(t.travel_guid)}
    assert_equal 'request_conflict',error.code
    assert_empty ShipTravel.all
    assert_equal before,assets
  end

end
