require 'test_helper'
require_relative '../../support/travel_repair_fixtures'
require_relative '../../support/fake_rabbitmq'

class Api::GateRoutingTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @hull.update!(location_name:@gate.name)
    @player.update_current_location!(@gate)
  end
  def configure(value,shard_id:@shard.id)
    setting=Setting.find_or_initialize_by(key:GateTravelRouting.setting_key(shard_id))
    setting.update!(value:value,setting_type:'text')
  end
  def jump(guid:'routing-test',**extra)
    post '/api/gate_travel',params:{secret_guid:'repair-secret',ship_guid:@hull.guid,travel_guid:guid}.merge(extra),as: :json
    JSON.parse(response.body)
  end
  def finish
    travel=ShipTravel.sole
    Tick.instance.update_columns(current_tick:travel.arrival_tick,sequence:travel.arrival_tick+1)
    broker=FakeRabbitmq::ChannelRecorder.new
    RabbitmqConnection.stub(:channel_for,broker.to_proc){ShipArrivalJob.perform_now}
    broker
  end
  test 'manual shard default selects dev for unqualified new jump and its arrival' do
    configure('dev')
    before=assets
    data=jump
    assert_response :success
    assert_equal 'dev',data['rabbitmq']
    assert_equal 'shard_default',data['rabbitmq_source']
    assert_equal 'dev',ShipTravel.sole.rabbitmq_environment
    assert_equal 'dev',TravelRequestReceipt.sole.request_context['rabbitmq_environment']
    broker=finish
    assert_equal ['dev'],broker.requested_environments
    assert_equal 1,broker.publications_for('dev').size
    assert_empty broker.publications_for('prod')
    assert_equal before,assets
  end
  test 'other shard default cannot affect this ship and unset default stays prod' do
    configure('dev',shard_id:@shard.id+1)
    data=jump
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
    assert_equal 'global_default',data['rabbitmq_source']
  end
  test 'explicit request wins over configured shard default' do
    configure('dev')
    data=jump(rabbitmq:'prod')
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
    assert_equal 'request',data['rabbitmq_source']
    assert_equal 'prod',ShipTravel.sole.rabbitmq_environment
  end
  test 'pending and completed retries keep original prod after default changes to dev' do
    jump
    configure('dev')
    before=[ShipTravel.sole.attributes,TravelRequestReceipt.sole.attributes]
    data=jump
    assert_response :success
    assert data['request_replayed']
    assert_equal 'prod',data['rabbitmq']
    assert_equal 'receipt',data['rabbitmq_source']
    assert_equal before,[ShipTravel.sole.attributes,TravelRequestReceipt.sole.attributes]
    assert_equal ['prod'],finish.requested_environments
    before=[@hull.reload.attributes,@player.reload.attributes,TravelArrivalEvent.sole.attributes]
    data=jump
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
    assert_equal 'completed',data['lifecycle_status']
    assert_equal 0,data['time_remaining']
    assert_equal before,[@hull.reload.attributes,@player.reload.attributes,TravelArrivalEvent.sole.attributes]
  end
  test 'saved dev receipt survives removing default and conflicting explicit prod is refused' do
    configure('dev')
    jump
    configure('')
    data=jump
    assert_response :success
    assert_equal 'dev',data['rabbitmq']
    before=[ShipTravel.sole.attributes,TravelRequestReceipt.sole.attributes]
    data=jump(rabbitmq:'prod')
    assert_response :unprocessable_entity
    assert_equal 'request_conflict',data['code']
    assert_equal before,[ShipTravel.sole.attributes,TravelRequestReceipt.sole.attributes]
  end
  test 'legacy prod receipt is not rerouted by shard setting' do
    jump
    receipt=TravelRequestReceipt.sole
    receipt.update!(request_context:{kind:'gate_travel',gateway:''})
    configure('dev')
    before=receipt.attributes
    data=jump
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
    assert_equal 'receipt',data['rabbitmq_source']
    assert_equal before,receipt.reload.attributes
  end
  test 'invalid configured default blocks new request without writes while explicit route works' do
    configure('invalid')
    before=[@hull.reload.attributes,@player.reload.attributes]
    data=jump
    assert_response :unprocessable_entity
    assert_equal 'invalid_rabbitmq_configuration',data['code']
    assert_empty ShipTravel.all
    assert_empty TravelRequestReceipt.all
    assert_equal before,[@hull.reload.attributes,@player.reload.attributes]
    data=jump(rabbitmq:'prod')
    assert_response :success
    assert_equal 'prod',data['rabbitmq']
  end
  test 'saved receipt replays even if configured default becomes invalid' do
    jump
    configure('invalid')
    data=jump
    assert_response :success
    assert data['request_replayed']
    assert_equal 'prod',data['rabbitmq']
  end
  test 'receipt from another ship cannot supply a broker or replay identity' do
    jump
    other=UserShip.create!(user:@user,ship:@catalog_ship,shard:@shard,shard_user:@player,
      guid:SecureRandom.uuid,total_scu:20,used_scu:0,location_name:@gate.name)
    configure('dev')
    selected=GateTravelRouting.resolve(user_ship:other,shard:@shard,travel_guid:'routing-test')
    assert_equal 'dev',selected.environment
    assert_equal 'shard_default',selected.source
    before=ShipTravel.sole.attributes
    post '/api/gate_travel',params:{secret_guid:'repair-secret',ship_guid:other.guid,travel_guid:'routing-test'},as: :json
    assert_response :unprocessable_entity
    assert_equal 'request_conflict',JSON.parse(response.body)['code']
    assert_equal before,ShipTravel.sole.attributes
    assert_equal 1,TravelRequestReceipt.count
  end
end
