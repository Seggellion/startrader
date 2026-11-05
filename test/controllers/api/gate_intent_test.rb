require 'test_helper'
require_relative '../../support/travel_repair_fixtures'
require_relative '../../support/fake_rabbitmq'

class Api::GateIntentTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @origin.update!(name:'Stanton Gateway (Pyro)',star_system_name:'Pyro')
    @destination.update!(name:'Pyro Gateway (Stanton)',star_system_name:'Stanton')
    @hull.update!(location_name:@origin.name)
    @player.update_current_location!(@origin)
  end

  def jump(guid:'outbound', environment:nil, **extra)
    path = '/api/gate_travel'
    path += "?rabbitmq=#{environment}" unless environment.nil?
    post path,params:{secret_guid:'repair-secret',ship_guid:@hull.guid,travel_guid:guid}.merge(extra),as: :json
    JSON.parse(response.body)
  end

  def complete(guid:'outbound', environment:'prod')
    travel=ShipTravel.find_by!(travel_guid:guid)
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick+1)
    broker=FakeRabbitmq::ChannelRecorder.new
    RabbitmqConnection.stub(:channel_for,broker.to_proc){ShipArrivalJob.perform_now}
    assert_equal [environment],broker.requested_environments
    assert_equal 'completed',TravelRequestReceipt.find_by!(travel_guid:guid).outcome
    broker
  end

  def state
    [@hull.reload.attributes,@player.reload.attributes,TravelRequestReceipt.order(:id).map(&:attributes),
      ShipTravel.order(:id).map(&:attributes),TravelArrivalEvent.order(:id).map(&:attributes),assets]
  end

  test 'fresh blank jump retains historical default production and canonical pending response' do
    data=jump
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
    assert_equal @origin.name,data['current_location']
    assert_equal @destination.name,data['arrival_location']
    assert_equal 'pending',data['lifecycle_status']
    assert_equal 120,data['time_remaining']
    assert_equal 'prod',ShipTravel.sole.rabbitmq_environment
  end

  test 'completed outbound followed by another blank fresh request is refused without reversing' do
    jump
    complete
    before=state
    data=jump(guid:'unqualified-repeat')
    assert_response :unprocessable_entity
    assert_equal 'jump_destination_required',data['code']
    assert_equal @destination.name,data['current_location']
    assert_equal 'Stanton',data['current_star_system']
    assert_equal 'completed',data['lifecycle_status']
    assert data['route_confirmation_required']
    assert_equal 'outbound',data['previous_travel_guid']
    assert_equal before,state
  end

  test 'intentional return by selected gateway remains available with preserved assets' do
    jump
    complete
    before=assets
    data=jump(guid:'intentional-return',gateway_name:'Pyro Gateway')
    assert_response :success
    assert_equal 'Pyro',data['arrival_star_system']
    assert_equal @destination.name,data['current_location']
    complete(guid:'intentional-return')
    assert_equal @origin.name,@hull.reload.location_name
    assert_equal before,assets
  end

  test 'expected current origin allows deliberate blank return and stale origin refuses it' do
    jump
    complete
    before=state
    data=jump(guid:'stale-origin',expected_origin_location:@origin.name)
    assert_response :unprocessable_entity
    assert_equal 'stale_jump_origin',data['code']
    assert_equal before,state
    data=jump(guid:'known-origin',expected_origin_location:@destination.name)
    assert_response :success
    assert_equal 'Pyro',data['arrival_star_system']
  end

  test 'explicit expected destination rejects unintentional reverse and allows intended return' do
    jump
    complete
    before=state
    data=jump(guid:'same-intent',expected_destination_location:@destination.name)
    assert_response :unprocessable_entity
    assert_equal 'jump_destination_mismatch',data['code']
    assert_equal before,state
    data=jump(guid:'return-intent',expected_destination_location:@origin.name)
    assert_response :success
    assert_equal 'Pyro',data['arrival_star_system']
  end

  test 'same completed request replays with zero remaining and saved route without moving again' do
    jump
    complete
    before=state
    data=jump
    assert_response :success
    assert data['request_replayed']
    assert_equal 'completed',data['lifecycle_status']
    assert_equal 0,data['time_remaining']
    assert_equal Tick.current,data['current_tick']
    assert_equal @destination.name,data['current_location']
    assert_includes data['message'],'already completed'
    assert_equal before,state
  end

  test 'development selector is persisted replay bound and used for natural dispatch' do
    data=jump(environment:'DEV')
    assert_response :success
    assert_equal 'dev',data['rabbitmq']
    assert_equal 'dev',ShipTravel.sole.rabbitmq_environment
    before=state
    data=jump(environment:'prod')
    assert_response :unprocessable_entity
    assert_equal 'request_conflict',data['code']
    assert_equal before,state
    complete(environment:'dev')
    before=state
    data=jump(environment:'dev')
    assert_response :success
    assert_equal 'dev',data['rabbitmq']
    assert_equal 0,data['time_remaining']
    assert_equal before,state
  end

  test 'invalid environment is rejected before due arrival or any other state change' do
    jump
    travel=ShipTravel.sole
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick+1)
    before=state
    data=jump(guid:'invalid',environment:'unknown')
    assert_response :unprocessable_entity
    assert_equal 'invalid_rabbitmq',data['code']
    assert_equal before,state
  end

  test 'legacy receipt context replays only its saved broker and is never rewritten' do
    jump
    receipt=TravelRequestReceipt.sole
    receipt.update!(request_context:{kind:'gate_travel',gateway:''})
    complete
    before=state
    data=jump
    assert_response :success
    assert data['request_replayed']
    assert_equal before,state
    data=jump(environment:'dev')
    assert_response :unprocessable_entity
    assert_equal 'request_conflict',data['code']
    assert_equal before,state
  end

  test 'paused journey and assets stay unchanged for both replay and fresh jump attempts' do
    jump
    travel=ShipTravel.sole
    travel.interdict!(100)
    before=state
    data=jump(guid:'new-while-paused',gateway_name:'Stanton Gateway')
    assert_response :unprocessable_entity
    assert_equal 'interdicted',data['code']
    assert_equal before,state
    data=jump
    assert_response :success
    assert_equal 'paused',data['lifecycle_status']
    assert_equal before,state
  end

  test 'guard commits an independently due arrival without starting another departure' do
    jump
    travel=ShipTravel.sole
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick+1)
    data=jump(guid:'ambiguous-after-due')
    assert_response :unprocessable_entity
    assert_equal 'jump_destination_required',data['code']
    assert_equal @destination.name,data['current_location']
    assert_equal @destination.name,@hull.reload.location_name
    assert_equal @destination.name,@player.reload.current_location_name
    assert_empty ShipTravel.all
    assert_equal 'completed',TravelRequestReceipt.sole.outcome
    assert_equal 1,TravelArrivalEvent.pending.count
  end

  test 'status after arrival exposes canonical root location for clients even with stale report' do
    jump
    complete
    post '/api/status',params:{secret_guid:'repair-secret',ship_guid:@hull.guid,ship_model:@catalog_ship.model,
      shard_uuid:@shard.channel_uuid,player_guid:@user.uid,player_name:@user.username,location:@origin.name},as: :json
    assert_response :success
    data=JSON.parse(response.body)
    assert_equal @destination.name,data['current_location']
    assert_equal @destination.name,data['player_location']
    assert_equal @destination.name,data.dig('ship','location')
    assert_equal 'stale_location',data.dig('location_sync','code')
    assert_equal @destination.name,@hull.reload.location_name
  end

  test 'explicit origin context cannot be changed on same request identity' do
    jump(expected_origin_location:@origin.name)
    before=state
    data=jump(expected_origin_location:@destination.name)
    assert_response :unprocessable_entity
    assert_equal 'request_conflict',data['code']
    assert_equal before,state
  end

  test 'body selector and existing direction aliases are accepted and auth is still required' do
    data=jump(guid:'body-dev',rabbitmq:' dev ',destination_gateway:'Stanton Gateway')
    assert_response :success
    assert_equal 'dev',data['rabbitmq']
    before=state
    post '/api/gate_travel?rabbitmq=dev',params:{ship_guid:@hull.guid,travel_guid:'unauthenticated'},as: :json
    assert_response :unauthorized
    assert_equal before,state
  end

  test 'stale explicit gateway cannot fuzzy match the reciprocal gateway after arrival' do
    jump
    complete
    before=state
    data=jump(guid:'stale-gateway',gateway_name:'Stanton Gateway')
    assert_response :unprocessable_entity
    assert_equal 'invalid_request',data['code']
    assert_equal before,state
    data=jump(guid:'wrong-qualified-origin',expected_origin_location:'Pyro Gateway (Nyx)')
    assert_response :unprocessable_entity
    assert_equal 'stale_jump_origin',data['code']
    assert_equal before,state
  end
end
