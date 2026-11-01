require %q(minitest/mock)
require_relative '../../test/controllers/api/gate_travel_controller_test'
class Api::GateTravelControllerTest
  test "discovery paused zero is persisted skipped and blocks gateway" do
    post_gate_travel(ship_guid: @user_ship.guid)
    travel=ShipTravel.last
    travel.interdict!(10)
    @user_ship.update!(status: 'interdicted')
    assert_equal 0,travel.reload.arrival_tick
    assert_equal 4,travel.remaining_ticks_from_arrival
    ShipArrivalJob.perform_now
    assert ShipTravel.exists?(travel.id)
    post_gate_travel(ship_guid: @user_ship.guid)
    assert_response :unprocessable_entity
    assert_equal 'Ship is already in transit.',response_json['message']
    assert_equal 1,ShipTravel.count
    travel.resume!(10)
    assert_equal 14,travel.reload.arrival_tick
  end

  test "discovery unpaused zero skips completion but does not block new jump at positive tick" do
    post_gate_travel(ship_guid: @user_ship.guid)
    travel=ShipTravel.last
    travel.update!(arrival_tick:0)
    ShipArrivalJob.perform_now
    assert ShipTravel.exists?(travel.id)
    post_gate_travel(ship_guid: @user_ship.guid)
    assert_response :success
    assert_equal 2,ShipTravel.count
  end

  test "discovery gateway selection from remote station strands player after successful arrival" do
    @user_ship.update!(location_name:@pyro_location.name)
    @shard_user.update_current_location!(@pyro_location)
    post_gate_travel(ship_guid:@user_ship.guid,gateway_name:'Nyx Gateway')
    assert_response :success
    travel=ShipTravel.last
    assert_equal @nyx_gateway_in_pyro,travel.from_location
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick)
    RabbitmqSender.stub(:send_ship_report,nil){ ShipArrivalJob.perform_now }
    assert_equal @pyro_gateway_in_nyx.name,@user_ship.reload.location_name
    assert_equal @pyro_location.name,@shard_user.reload.current_location_name
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :unprocessable_entity
    assert_equal "Ship is at #{@pyro_gateway_in_nyx.name}, but player is at #{@pyro_location.name}.",response_json['message']
    assert_equal 0,ShipTravel.count
  end

  test "discovery co-located gateway departure updates player and permits return" do
    @shard_user.update_current_location!(@origin_gateway)
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :success
    travel=ShipTravel.last
    Tick.instance.update_columns(current_tick:travel.arrival_tick+3,sequence:travel.arrival_tick+3)
    reports=0
    RabbitmqSender.stub(:send_ship_report,->(_){reports+=1}) do
      ShipArrivalJob.perform_now
      ShipArrivalJob.perform_now
    end
    assert_equal 1,reports
    assert_equal @arrival_gateway.name,@shard_user.reload.current_location_name
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :success
    assert_equal 1,ShipTravel.count
  end

  test "discovery due arrival in gateway availability uses stale player instance" do
    @shard_user.update_current_location!(@origin_gateway)
    post_gate_travel(ship_guid:@user_ship.guid)
    travel=ShipTravel.last
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick)
    RabbitmqSender.stub(:send_ship_report,nil){post_gate_travel(ship_guid:@user_ship.guid)}
    assert_response :unprocessable_entity
    assert_equal "Ship is at #{@arrival_gateway.name}, but player is at #{@origin_gateway.name}.",response_json['message']
    assert_equal @arrival_gateway.name,@shard_user.reload.current_location_name
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :success
  end

  test "discovery duplicate request creates one journey but returns rejection" do
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :success
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :unprocessable_entity
    assert_equal 'Ship is already in transit.',response_json['message']
    assert_equal 1,ShipTravel.count
  end

  test "discovery gateway transaction rolls back but ordinary writer can partially persist" do
    service=GateTravelService.new(ship_guid:@user_ship.guid,start_tick:10)
    before=ShipTravel.count
    @user_ship.stub(:update!,->(*){raise 'synthetic ship write failure'}) do
      assert_raises(RuntimeError){service.send(:create_gate_travel!,user_ship:@user_ship,origin_location:@origin_gateway,arrival_location:@arrival_gateway)}
    end
    assert_equal before,ShipTravel.count
    seed_orbital_catalog
    @user_ship.update!(location_name:@non_gateway.name)
    @non_gateway.update!(parent_name:'Crusader')
    dest=Location.create!(name:'Discovery Area18',classification:'city',star_system_name:'Stanton',parent_name:'ArcCorp')
    @user_ship.stub(:update!,->(*){raise 'synthetic ship write failure'}) do
      assert_raises(RuntimeError){TravelService.new(user_ship:@user_ship,to_location:dest,travel_guid:'discovery-partial',start_tick:10).call}
    end
    assert_equal before+1,ShipTravel.count
    assert_operator ShipTravel.last.arrival_tick,:>,0
    assert_equal @non_gateway.name,@user_ship.reload.location_name
    refute_equal 'in_transit',@user_ship.status
  end

  test "discovery tick zero remains positive with gateway duration and ordinary minimum" do
    Tick.instance.update_columns(current_tick:0,sequence:1)
    Setting.find_by!(key:'seconds_per_tick').update!(value:'15')
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :success
    assert_equal 0,ShipTravel.last.departure_tick
    assert_equal 8,ShipTravel.last.arrival_tick
    assert_equal 2,TravelTiming.duration_ticks(0)
    assert_raises(ArgumentError){TravelTiming.duration_ticks(Float::NAN)}
    assert_raises(ArgumentError){TravelTiming.duration_ticks(-1)}
  end
end
class Api::GateTravelControllerTest
  test "discovery broker failure is followed by destructive stale cleanup on tick" do
    @shard_user.update_current_location!(@origin_gateway)
    post_gate_travel(ship_guid:@user_ship.guid)
    travel=ShipTravel.last
    Tick.instance.update_columns(current_tick:travel.arrival_tick-1,sequence:travel.arrival_tick-1)
    RabbitmqSender.stub(:send_ship_report,->(_){raise IOError,'synthetic broker failure'}) do
      MarketPriceUpdater.stub(:update_prices!,nil){Tick.increment!}
    end
    refute ShipTravel.exists?(travel.id)
    assert_equal @origin_gateway.name,@user_ship.reload.location_name
    assert_equal @origin_gateway.name,@shard_user.reload.current_location_name
    assert_equal 'aimlessly floating in space',@user_ship.status
  end

  test "discovery missing reciprocal gateway rejects otherwise eligible ship without zero" do
    @wrong_system_gateway.destroy!
    @origin_gateway.update!(name:'Terra Gateway (Stanton)')
    @user_ship.update!(location_name:@origin_gateway.name)
    @shard_user.update_current_location!(@origin_gateway)
    post_gate_travel(ship_guid:@user_ship.guid)
    assert_response :unprocessable_entity
    assert_equal 'No valid destination Jumpgate found.',response_json['message']
    assert_equal 0,ShipTravel.count
  end
end
