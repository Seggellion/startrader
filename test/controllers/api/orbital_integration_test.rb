require 'test_helper'
require_relative '../../support/orbital_fixtures'

class Api::OrbitalIntegrationTest < ActionDispatch::IntegrationTest
  include OrbitalFixtures
  setup do
    seed_orbital_catalog
    MarketPriceUpdater.stub(:update_prices!, nil) { Tick.create!(current_tick: 0, sequence: 1) }
  end

  test 'quote captures one read-only tick and returns physical units and identity' do
    calls = 0
    OrbitalState.stub(:current_tick!, -> { calls += 1; 0 }) do
      assert_no_difference ['Tick.count', 'ShipTravel.count', 'Location.count'] do
        post '/api/distance_calculator', params: {distance: {from: 'Hurston', to: 'Crusader'}}, as: :json
      end
    end
    assert_response :success
    body = response.parsed_body
    assert_equal 1, calls
    assert_equal 0, body['current_tick']
    assert_equal 'Gm', body['distance_unit']
    assert_equal OrbitalState.catalog.version, body['catalog_version']
    expected = Math.sqrt(569 - 520 * Math.cos(75 * Math::PI / 180))
    assert_in_delta expected, body['distance'], 1e-9
    assert_in_delta 13, body['from_position_gm']['x'], 1e-9
  end

  test 'equal-radius P4 and P5 remain opposite and Delamar hosts Levski' do
    state = OrbitalState.snapshot(tick: 0)
    p4 = Location.find_by!(name: 'Pyro IV'); p5 = Location.find_by!(name: 'Pyro V')
    assert_in_delta 95.2, state.distance(p4.id, p5.id), 1e-9
    city = Location.find_by!(name: 'Levski'); host = Location.find_by!(name: 'Delamar')
    assert_equal 0, state.distance(city.id, host.id)
    assert_equal 'host_center_approximation', state.report(city.id)[:point_reference]
    assert_in_delta 15, Orbital::Geometry.distance({x:0,y:0,z:0}, state.position(city.id)), 1e-9
  end

  test 'aliases work and cross-system quotes and unmeasured bodies are unavailable' do
    post '/api/distance_calculator', params: {distance: {from: 'Pyro 4', to: 'P5'}}, as: :json
    assert_response :success
    assert_in_delta 95.2, response.parsed_body['distance'], 1e-9
    post '/api/distance_calculator', params: {distance: {from: 'Hurston', to: 'Nyx I'}}, as: :json
    assert_response :unprocessable_entity
    moon = Location.create!(name: 'Unmeasured moon', classification: 'moon', star_system_name: 'Stanton', parent_name: 'Hurston')
    post '/api/distance_calculator', params: {distance: {from: 'Hurston', to_id: moon.id}}, as: :json
    assert_response :unprocessable_entity
    assert_match(/Unmeasured/, response.parsed_body['error'])
  end

  test 'map and API expose the effective catalog despite changed imported fields' do
    get '/locations', params: {star: 'Stanton', tick: 0}
    assert_response :success
    body = response.parsed_body.find { |r| r['attributes']['name'] == 'Hurston' }['attributes']
    assert_equal 13, body['periapsis']
    assert_in_delta 13, body['position_gm']['x'], 1e-9
    assert_equal 0, body['current_tick']
    get '/locations', params: {star: 'Stanton', version: 'stale'}
    assert_response :conflict
    get '/api/locations', params: {system: 'Stanton'}
    assert_response :success
    star = response.parsed_body['data'].find { |r| r['attributes']['name'] == 'Stanton' }['attributes']
    assert_equal 1.98847e30, star['mass']
    assert_equal 'kg', star['mass-unit']
  end

  test 'duration consumes physical distance and validates speed without a fivefold rewrite' do
    from = Location.find_by!(name: 'Pyro IV'); to = Location.find_by!(name: 'Pyro V')
    assert_equal 48, TravelTimeCalculator.new(ship: Ship.new(speed: 2), from_location: from, to_location: to, start_tick: 0).calculate
    assert_raises(ArgumentError) do
      TravelTimeCalculator.new(ship: Ship.new(speed: 0), from_location: from, to_location: to, start_tick: 0).calculate
    end
  end

  test 'new travel uses canonical aliases and physical distance without changing saved journeys' do
    from = Location.find_by!(name: 'Pyro IV'); to = Location.find_by!(name: 'Pyro V')
    user = User.create!(username:'OrbitalPilot', twitch_id:'orbital-pilot', uid:'orbital-pilot', user_type:'player')
    shard = Shard.create!(name:'Orbital Test', region:'us', channel_uuid:'orbital-shard')
    player = ShardUser.create!(user:user, shard:shard, shard_name:shard.name)
    player.update_current_location!(from)
    ship = Ship.create!(model:'Orbital Test Ship', slug:'orbital-test', speed:2, scu:4)
    hull = UserShip.create!(user:user, ship:ship, shard:shard, shard_user:player,
      shard_name:shard.name, guid:'orbital-hull', ship_slug:ship.slug, location_name:from.name, total_scu:4, used_scu:0, status:'docked')
    post '/api/travel?rabbitmq=dev', params: {ship_travel: {ship_guid:hull.guid,
      ship_slug:ship.slug, player_guid:user.twitch_id, player_name:user.username,
      shard_uuid:shard.channel_uuid, from_location:'P4', to_location:'P5', travel_guid:'orbital-journey'}}, as: :json
    assert_response :success
    journey = ShipTravel.find_by!(travel_guid:'orbital-journey')
    assert_equal 48, journey.total_duration_ticks
    assert_equal 48, journey.arrival_tick
    assert_equal 'dev', journey.rabbitmq_environment
    assert_equal from.id, journey.from_location_id
    assert_equal to.id, journey.to_location_id
    before = journey.attributes.slice('arrival_tick','total_duration_ticks','is_paused','remaining_ticks_from_arrival')
    OrbitalState.snapshot(tick:100).distance(from.id,to.id)
    assert_equal before, journey.reload.attributes.slice(*before.keys)
    assert_not from.destroy
    assert ShipTravel.exists?(journey.id)
  end
end
