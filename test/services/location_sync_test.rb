require 'test_helper'
require_relative '../support/travel_repair_fixtures'

# M03 — single location writer, instrumentation and delivery guard (F-03, F-20).
class LocationSyncTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup { setup_travel_repair }

  test 'player write records source and time only when the location changes' do
    @player.update_columns(location_updated_at: nil, location_source: nil)
    LocationSync.player!(@player, @origin, source: 'repair')
    assert_nil @player.reload.location_source, 'unchanged location must not touch the markers'

    LocationSync.player!(@player, @destination, source: 'client_status')
    @player.reload
    assert_equal @destination.name, @player.current_location_name
    assert_equal 'client_status', @player.location_source
    assert_in_delta Time.current, @player.location_updated_at, 5
  end

  test 'legacy coordinate keys survive a named-location write' do
    @player.update_columns(last_location: { 'name' => @origin.name, 'x' => 1.5, 'y' => -2, 'z' => 3 })
    LocationSync.player!(@player.reload, @destination, source: 'admin')
    payload = @player.reload.last_location
    assert_equal [1.5, -2, 3], payload.values_at('x', 'y', 'z')
    assert_equal @destination.name, payload['name']
    assert_equal @destination.id, payload['id']
  end

  test 'unknown sources are refused' do
    assert_raises(ArgumentError) { LocationSync.player!(@player, @destination, source: 'guess') }
  end

  test 'ship and player change together or not at all' do
    failing = ->(*) { raise ActiveRecord::RecordInvalid.new(@player) }
    @player.stub(:update_current_location!, failing) do
      assert_raises(ActiveRecord::RecordInvalid) do
        LocationSync.both!(ship: @hull, player: @player, location: @destination, source: 'repair')
      end
    end
    assert_equal @origin.name, @hull.reload.location_name
    assert_equal @origin.name, @player.reload.current_location_name
  end

  test 'departure from the co-located origin is a no-op and arrival records its authority' do
    walk_to_gate!
    walked_at = @player.reload.location_updated_at
    travel = gate_start
    assert_equal 'travel_arrival', @player.reload.location_source, 'already at origin: markers untouched'
    assert_equal walked_at, @player.location_updated_at
    ShipTravelArrivalProcessor.new(travel: travel, current_tick: travel.arrival_tick, notify: false).call
    assert_equal 'travel_arrival', @player.reload.location_source
    assert_equal @destination.name, @player.current_location_name
    assert_equal @destination.name, @hull.reload.location_name
  end

  test 'delivery is refused while a journey is unfinished and never moves the player' do
    travel = gate_start
    before = location_state
    post '/api/ships/deliver_ship', params: { ship_guid: @hull.guid, location: @destination.name, secret_guid: 'repair-secret' }
    assert_equal 'error', response.parsed_body['Status']
    assert_match(/unfinished journey/, response.parsed_body['ErrorText'])
    assert_equal before, location_state
    assert ShipTravel.exists?(travel.id)

    ShipTravelArrivalProcessor.new(travel: travel, current_tick: travel.arrival_tick, notify: false).call
    player_before = @player.reload.current_location_name
    post '/api/ships/deliver_ship', params: { ship_guid: @hull.guid, location: @origin.name, secret_guid: 'repair-secret' }
    assert_equal 'success', response.parsed_body['Status']
    assert_equal @origin.name, @hull.reload.location_name
    assert_equal player_before, @player.reload.current_location_name
  end
end
