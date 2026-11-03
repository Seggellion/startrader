require 'test_helper'
require_relative '../../support/travel_repair_fixtures'

class Api::StatusLocationSyncTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup { setup_travel_repair }

  def payload
    {ship_guid: @hull.guid, ship_model: @catalog_ship.model, shard_uuid: @shard.channel_uuid,
      player_guid: @user.uid, player_name: @user.username, location: @gate.name, secret_guid: 'repair-secret'}
  end

  def complete_gate
    travel = gate_start
    ShipTravelArrivalProcessor.new(travel: travel, current_tick: travel.arrival_tick).call
  end

  test 'flat and nested status replies return canonical completed location and ignored report warning' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    [payload, {trade: payload}].each do |body|
      post '/api/status', params: body, as: :json
      assert_response :success
      reply = response.parsed_body
      assert_equal @destination.name, reply['player_location']
      assert_equal @destination.name, reply.dig('ship', 'location')
      assert_equal 'stale_location', reply.dig('location_sync', 'code')
      assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
    end
  end

  test 'legacy status reply cannot revert a completed arrival' do
    complete_gate
    post '/api/status', params: {username: @user.username, shard: @shard.channel_uuid,
      location: @gate.name, secret_guid: 'repair-secret'}, as: :json
    assert_response :success
    assert_equal @destination.name, response.parsed_body['player_location']
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal %w[ship player], response.parsed_body.dig('location_sync', 'ignored_for')
  end

  test 'paused zero journey and mismatched player remain unchanged through status' do
    travel = saved_trip
    travel.interdict!(95)
    @player.update_current_location!(@destination)
    before = [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes, assets]
    post '/api/status', params: payload.merge(location: @origin.name), as: :json
    assert_response :success
    assert_equal 'interdicted', response.parsed_body.dig('ship', 'travel_state')
    assert_equal 0, response.parsed_body.dig('ship', 'arrival_tick')
    assert_equal @destination.name, response.parsed_body['player_location']
    assert_equal before, [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes, assets]
  end

  test 'unauthenticated stale status still cannot change records' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    post '/api/status', params: payload.except(:secret_guid), as: :json
    assert_response :unauthorized
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
  end
end
