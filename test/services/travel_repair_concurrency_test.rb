require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class TravelRepairConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests=false
  include TravelRepairFixtures
  include ActiveJob::TestHelper
  setup { setup_travel_repair }
  teardown { cleanup_travel_repair }
  def race(*actions)
    ready=Queue.new; start=Queue.new
    threads=actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |c|
          c.execute("SET lock_timeout='4s'")
          ready << c.select_value('SELECT pg_backend_pid()')
          start.pop
          begin
            [:ok,action.call]
          rescue TravelLifecycle::Error,ActiveRecord::RecordNotFound => error
            [:refused,error.class.name]
          ensure
            c.execute('RESET lock_timeout')
          end
        end
      end
    end
    pids=threads.map{ready.pop}
    assert_equal pids.size,pids.uniq.size,'independent PostgreSQL backends required'
    threads.size.times{start << true}
    threads.map do |thread|
      assert thread.join(10),'concurrency schedule timed out'
      thread.value
    end
  ensure
    threads&.each{|t|t.kill if t.alive?}
  end
  test 'two simultaneous starts with one GUID replay one durable departure' do
    results=race(-> {gate_start('same-guid')},-> {gate_start('same-guid')})
    assert results.all?{|r|r.first==:ok}
    assert_equal 1,ShipTravel.count
    assert_equal 1,TravelRequestReceipt.count
    assert_equal 1,results.map{|r|r.last}.count(&:request_replayed)
  end
  test 'simultaneous ordinary and gate starts with different GUIDs allow only one' do
    target=@gate
    ordinary=-> {
      calculator=Struct.new(:calculate).new(2)
      TravelTimeCalculator.stub(:new,calculator) do
        TravelService.new(user_ship:UserShip.find(@hull.id),to_location:target,travel_guid:'ordinary-race').call
      end
    }
    results=race(ordinary,-> {gate_start('gate-race')})
    assert_equal 1,results.count{|r|r.first==:ok}
    assert_equal 1,ShipTravel.count
    assert_equal 1,TravelRequestReceipt.count
  end
  test 'pause racing arrival and resume racing arrival respect ship first locks' do
    t=gate_start
    # At the due tick the arrival window remains eligible.
    results=race(-> {ShipTravel.find(t.id).interdict!(108,enforce_window:true)},
      -> {ShipTravelArrivalProcessor.new(travel:ShipTravel.find(t.id),current_tick:108).call})
    refute results.empty?
    if ShipTravel.exists?(t.id)
      assert ShipTravel.find(t.id).is_paused?
      race(-> {ShipTravel.find(t.id).resume!(200)},
        -> {ShipTravelArrivalProcessor.new(travel:ShipTravel.find(t.id),current_tick:201).call})
      assert_operator ShipTravel.where(user_ship_id:@hull.id).count,:<=,1
    else
      assert_equal 1,TravelArrivalEvent.count
      assert_equal @destination.name,@hull.reload.location_name
    end
  end
  test 'cancellation racing arrival cannot resurrect or double finalize journey' do
    t=gate_start
    race(-> {ShipTravel.find(t.id).cleanup_after_cancellation!(108)},
      -> {ShipTravelArrivalProcessor.new(travel:ShipTravel.find(t.id),current_tick:108).call})
    assert_empty ShipTravel.all
    assert_equal 1,TravelRequestReceipt.count
    assert_operator TravelArrivalEvent.count,:<=,1
  end
  test 'two dispatchers claim a pending event once while independently connected' do
    t=gate_start
    ShipTravelArrivalProcessor.new(travel:t,current_tick:108).call
    calls=Queue.new
    RabbitmqSender.stub(:send_arrival_event,->(event){calls << event.event_guid}) do
      race(-> {TravelArrivalDispatchJob.perform_now},-> {TravelArrivalDispatchJob.perform_now})
    end
    assert_equal 1,calls.size
    assert TravelArrivalEvent.sole.sent_at
  end
  test 'resume racing processor on a guaranteed paused journey cannot double complete' do
    t=gate_start
    t.interdict!(100)
    race(-> {ShipTravel.find(t.id).resume!(200)},
      -> {ShipTravelArrivalProcessor.new(travel:ShipTravel.find(t.id),current_tick:201).call})
    assert_equal 1,ShipTravel.count
    assert_equal 208,ShipTravel.sole.arrival_tick
    assert_not ShipTravel.sole.is_paused?
    assert_equal 'in_transit',@hull.reload.status
    assert_equal 0,TravelArrivalEvent.count
  end

  test 'commit remains durable if enqueue callback fails and independent sweep recovers' do
    t=gate_start
    TravelArrivalDispatchJob.stub(:perform_later,->(*){raise 'synthetic enqueue outage'}) do
      ShipTravelArrivalProcessor.new(travel:t,current_tick:108).call
    end
    assert_empty ShipTravel.all
    assert_equal 1,TravelArrivalEvent.pending.count
    RabbitmqSender.stub(:send_arrival_event,nil){TravelArrivalDispatchJob.perform_now}
    assert_empty TravelArrivalEvent.pending
    assert_equal 'completed',TravelRequestReceipt.sole.outcome
  end

  test 'broker failure schedules durable retry after commit even when ticks are stopped' do
    t=gate_start
    ShipTravelArrivalProcessor.new(travel:t,current_tick:108).call
    event=TravelArrivalEvent.sole
    previous_adapter=ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter=:delayed_job
    before=Delayed::Job.pluck(:id)
    RabbitmqSender.stub(:send_arrival_event,->(_){raise IOError,'synthetic broker outage'}) {event.deliver!}
    retry_job=Delayed::Job.where(queue:'travel_notifications').where.not(id:before).sole
    assert_includes retry_job.handler,'TravelArrivalDispatchJob'
    assert_in_delta event.reload.next_attempt_at.to_f,retry_job.run_at.to_f,0.01
    assert_nil event.reload.sent_at
    assert event.next_attempt_at
    assert_equal 1,event.attempts
    assert_equal 'completed',TravelRequestReceipt.sole.outcome
  ensure
    ActiveJob::Base.queue_adapter=previous_adapter if previous_adapter
  end

  test 'legacy GUID reuse is refused without acquiring a new request lock or abandoning the old journey' do
    legacy=saved_trip
    seen=[]
    original=TravelRequestReceipt.method(:lock_guid!)
    TravelRequestReceipt.stub(:lock_guid!,->(guid){seen << guid;original.call(guid)}) do
      e=assert_raises(TravelLifecycle::Error){gate_start(legacy.travel_guid)}
      assert_equal 'request_conflict',e.code
    end
    assert_empty seen
    assert ShipTravel.exists?(legacy.id)
    assert_empty TravelRequestReceipt.all
  end

  test 'lazy completion locks legacy identity before fresh request identity' do
    legacy=saved_trip
    seen=[]
    original=TravelRequestReceipt.method(:lock_guid!)
    TravelRequestReceipt.stub(:lock_guid!,->(guid){seen << guid;original.call(guid)}) do
      GateTravelService.new(ship_guid:@hull.guid,travel_guid:'fresh-after-legacy').call
    end
    assert_operator seen.index(legacy.travel_guid),:<,seen.index('fresh-after-legacy')
    assert_equal 1,ShipTravel.count
    assert_equal 'completed',TravelRequestReceipt.find_by!(travel_guid:legacy.travel_guid).outcome
  end

  test 'supported ship destruction racing arrival uses parent before dependent journey locks' do
    t=gate_start
    race(-> {UserShip.find(@hull.id).destroy!},
      -> {ShipTravelArrivalProcessor.new(travel:ShipTravel.find(t.id),current_tick:108).call})
    assert_not UserShip.exists?(@hull.id)
    assert_empty ShipTravel.where(user_ship_id:@hull.id)
    assert_operator TravelArrivalEvent.count,:<=,1
  end

end
