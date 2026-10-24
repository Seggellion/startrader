require 'test_helper'
require 'minitest/mock'
require_relative '../support/fake_rabbitmq'
require_relative '../../lib/travel_timing'

class TravelTimingPipelineTest < ActiveSupport::TestCase
  T = 1000

  setup do
    @adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :delayed_job
    Delayed::Job.delete_all
    TickControl.delete_all
    Setting.delete_all
    ActiveRecord::Base.connection.execute('DELETE FROM ticks')
    ShipTravel.delete_all
    Setting.create!(key:'seconds_per_tick',value:'15',setting_type:'text')
    Setting.create!(key:'hours_per_tick',value:'168',setting_type:'text')
    @now=Time.utc(2026,10,24,12)
    travel_to(@now)
    MarketPriceUpdater.stub(:update_prices!,nil) { Tick.create!(current_tick:T,sequence:1) }
    TickControl.instance.update!(running:true)
    @star=Location.create!(name:'Timing Star',api_id:9900,classification:'star_system',star_system_name:'Timing')
    @from=Location.create!(name:'Timing Origin',api_id:9901,classification:'planet',star_system_name:'Timing',parent_name:@star.name)
    @to=Location.create!(name:'Timing Destination',api_id:9902,classification:'planet',star_system_name:'Timing',parent_name:@star.name)
    @ship=Ship.create!(model:'Timing Ship',name:'Timing Ship',slug:'timing-ship',speed:2,scu:4)
    user=User.create!(username:'TimingPilot',twitch_id:'timing-pilot',uid:'timing-pilot',user_type:'player')
    shard=Shard.create!(name:'Timing Shard',region:'us',channel_uuid:'timing-shard')
    @player=ShardUser.create!(user:user,shard:shard,shard_name:shard.name)
    @player.update_current_location!(@from)
    @hull=UserShip.create!(user:user,ship:@ship,shard:shard,shard_user:@player,guid:'timing-hull',
      ship_slug:@ship.slug,location_name:@from.name,total_scu:4,used_scu:0,status:'docked')
    # Remove unrelated fixture/callback jobs before starting the real Tick chain.
    Delayed::Job.delete_all
  end

  teardown do
    Delayed::Job.delete_all
    ActiveJob::Base.queue_adapter = @adapter
    travel_back
  end

  def catalog(distance)
    Orbital::Catalog.new(data:{'version'=>'controlled-timing-fixture','status'=>'approved',
      'units'=>{'distance'=>'Gm','mass'=>'kg','time'=>'seconds','phase'=>'degrees'},
      'clock'=>{'epoch'=>'2026-10-24T12:00:00Z','origin_tick'=>T,'origin_simulation_seconds'=>0,
        'simulated_seconds_per_tick'=>604800,'orbital_progression'=>[{'activation_tick'=>T,'orbital_progression_multiplier'=>0.01}]},
      'bodies'=>[@star,@from,@to].map do |location|
        body={'name'=>location.name,'api_id'=>location.api_id,'classification'=>location.classification,
          'system'=>'Timing','parent'=>location.parent_name}
        if location==@star
          body['mass_kg']=1.98847e30
        else
          radius=location==@from ? 10.0 : 10.0+distance
          body.merge!('periapsis_gm'=>radius,'apoapsis_gm'=>radius,'phase_deg'=>0)
        end
        body
      end})
  end

  def simulation(distance=30)
    recorder=FakeRabbitmq::ChannelRecorder.new
    server=Object.new
    server.define_singleton_method(:broadcast) { |_channel,_payload| }
    OrbitalState.stub(:catalog,catalog(distance)) do
      MarketPriceUpdater.stub(:update_prices!,nil) do
        ActionCable.stub(:server,server) do
          RabbitmqConnection.stub(:channel_for,recorder.to_proc) { yield recorder }
        end
      end
    end
  end

  def depart
    TravelService.new(user_ship:@hull,from_location:@from,to_location:@to,
      travel_guid:'controlled-journey',rabbitmq_environment:'dev').call
  end

  def advance
    job=TickJob.job_scope.where(failed_at:nil).sole
    assert_equal @now+15.seconds,job.run_at
    @now=job.run_at
    travel_to(@now)
    before=Tick.current
    # Execute the real queued ActiveJob through the actual delayed worker.
    # No direct arrival processor invocation or final-tick assignment.
    assert_equal [1,0],Delayed::Worker.new(queues:['default']).work_off(1)
    assert_equal before+1,Tick.current
    assert_equal 1,TickJob.pending_count
  end

  [28,30,36].each do |distance|
    test "#{distance} physical Gm arrives once through scheduled Tick service" do
      simulation(distance) do |broker|
        travel=depart
        assert_equal distance,travel.total_duration_ticks
        assert_equal T,travel.departure_tick
        assert_equal T+distance,travel.arrival_tick
        assert_equal distance*15,travel.seconds_remaining(T)
        TickJob.ensure_scheduled!(wait:15.seconds)
        (distance-1).times { advance }
        assert ShipTravel.exists?(travel.id)
        assert_equal 'in_transit',@hull.reload.status
        assert_equal @from.name,@hull.location_name
        assert_empty broker.requested_environments
        assert_equal 15,travel.reload.seconds_remaining(Tick.current)
        advance
        refute ShipTravel.exists?(travel.id)
        assert_equal Time.utc(2026,10,24,12)+distance*15.seconds,Time.current
        assert_equal @to.name,@hull.reload.location_name
        assert_equal 'in orbit',@hull.status
        assert_equal @to.id,@player.reload.current_location.id
        assert_equal ['dev'],broker.requested_environments
        assert_equal 1,broker.publications_for('dev').size
        assert_includes broker.publications_for('dev').first[:message],'|ShipArrival|'
        advance
        assert_equal 1,broker.publications_for('dev').size
        assert_empty broker.publications_for('prod')
      end
    end
  end

  test 'ceiling boundaries and two tick minimum use physical units' do
    {0=>2,0.001=>2,1.999=>2,2=>2,2.000001=>3,27.99999=>28,28=>28,30=>30,30.000001=>31,36=>36,36.001=>37}.each do |distance,ticks|
      assert_equal ticks,TravelTiming.duration_ticks(distance)
    end
    [-1,nil,Float::NAN,Float::INFINITY].each { |bad| assert_raises(ArgumentError) { TravelTiming.duration_ticks(bad) } }
    simulation(0.001) { assert_equal 2,depart.total_duration_ticks }
  end

  test 'fractional physical distance uses the normal service ceiling' do
    simulation(30.000001) do
      travel=depart
      assert_equal 31,travel.total_duration_ticks
      assert_equal T+31,travel.arrival_tick
      assert_equal 465,travel.seconds_remaining(T)
    end
  end

  test 'missing tick setting defaults to fifteen seconds and keeps two minute gateways' do
    Setting.where(key:'seconds_per_tick').delete_all
    assert_equal 15,Tick.seconds_per_tick
    assert_equal 8,GateTravelService.allocate.send(:gate_travel_duration_ticks)
  end

  test 'ship reference speeds and imports cannot change ordinary effective rate' do
    simulation do
      [nil,0,-1,2,100].each do |raw|
        @ship.update!(speed:raw)
        assert_equal 30,TravelTimeCalculator.new(ship:@ship,from_location:@from,to_location:@to,start_tick:T).calculate
      end
      assert Admin::Data::ShipsImporter.import_ship({'id'=>9999,'name'=>'Timing Import','slug'=>'timing-import','scu'=>4,'speed'=>10000})
      imported=Ship.find_by!(api_id:9999)
      assert_nil imported.speed
      assert_equal 30,TravelTimeCalculator.new(ship:imported,from_location:@from,to_location:@to,start_tick:T).calculate
      @ship.update!(speed:2)
      result=Admin::Data::StarbitizenShipImporter.import_payload([{'shipname'=>@ship.name,'speed'=>10000,'cargocapacity'=>4}])
      assert_equal 1,result.updated_count
      assert_equal 2,@ship.reload.speed
      assert_equal 30,TravelTimeCalculator.new(ship:@ship,from_location:@from,to_location:@to,start_tick:T).calculate
    end
  end

  test 'departure boundary captures one tick for availability distance and arrival' do
    simulation do
      reads=0
      OrbitalState.stub(:current_tick!,-> { reads+=1; T+reads-1 }) do
        travel=depart
        assert_equal 1,reads
        assert_equal T,travel.departure_tick
        assert_equal 30,travel.total_duration_ticks
        assert_equal T+30,travel.arrival_tick
      end
    end
  end

  test 'paused sentinel survives real ticks and resumes remaining saved duration' do
    simulation do |broker|
      travel=depart
      TickJob.ensure_scheduled!(wait:15.seconds)
      5.times { advance }
      travel.interdict!(Tick.current)
      @hull.update!(status:'interdicted')
      assert_equal 0,travel.reload.arrival_tick
      assert_equal 25,travel.remaining_ticks_from_arrival
      saved=travel.attributes
      30.times { advance }
      assert_equal saved,travel.reload.attributes
      assert_empty broker.requested_environments
      travel.resume!(Tick.current)
      @hull.update!(status:'in_transit')
      assert_equal T+60,travel.arrival_tick
      24.times { advance }
      assert ShipTravel.exists?(travel.id)
      advance
      refute ShipTravel.exists?(travel.id)
      assert_equal ['dev'],broker.requested_environments
      advance
      assert_equal 1,broker.publications_for('dev').size
    end
  end

  test 'already saved faster journey retains arrival and is not recalculated' do
    simulation do |broker|
      travel=ShipTravel.create!(user_ship:@hull,from_location:@from,to_location:@to,
        travel_guid:'existing-journey',departure_tick:T,arrival_tick:T+15,total_duration_ticks:15,
        interdict_window_percent:15,rabbitmq_environment:'dev')
      @hull.update!(status:'in_transit')
      saved=travel.attributes
      assert_equal 30,TravelTiming.duration_ticks(@from.distance_to(@to,T))
      assert_equal saved,travel.reload.attributes
      TickJob.ensure_scheduled!(wait:15.seconds)
      14.times { advance }
      assert_equal saved,travel.reload.attributes
      assert_empty broker.requested_environments
      advance
      refute ShipTravel.exists?(travel.id)
      assert_equal 1,broker.publications_for('dev').size
    end
  end
end
