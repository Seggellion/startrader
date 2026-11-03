require 'test_helper'
require_relative '../support/travel_repair_fixtures'

class StatusLocationSyncTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup { setup_travel_repair }

  def report(location, **extra)
    TradeService.status(ship_guid: @hull.guid, ship_model: @catalog_ship.model,
      shard_uuid: @shard.channel_uuid, player_guid: @user.uid, player_name: @user.username,
      location: location, **extra)
  end

  def complete_gate
    travel = gate_start
    ShipTravelArrivalProcessor.new(travel: travel, current_tick: travel.arrival_tick).call
    travel
  end

  test 'stale status cannot undo a completed gate arrival or alter durable completion' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes, assets,
      TravelRequestReceipt.sole.attributes, TravelArrivalEvent.sole.attributes]
    response = report(@gate.name)
    assert_equal @destination.name, response.dig(:ship, :location)
    assert_equal @destination.name, response[:player_location]
    assert_equal 'stale_location', response.dig(:location_sync, :code)
    assert_equal %w[ship player], response.dig(:location_sync, :ignored_for)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes, assets,
      TravelRequestReceipt.sole.attributes, TravelArrivalEvent.sole.attributes]
  end

  test 'matching report confirms canonical locations without changing response shape' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    response = report(@destination.name)
    assert_equal 'success', response[:status]
    refute response.key?(:location_sync)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
  end

  test 'ordinary completion is protected even after journey cleanup and without an outbox' do
    travel = saved_trip
    ShipTravelArrivalProcessor.new(travel: travel, current_tick: 100, notify: false).call
    assert_empty ShipTravel.all
    assert_empty TravelArrivalEvent.all
    response = report(@origin.name)
    assert_equal @destination.name, response[:player_location]
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal 'completed', TravelRequestReceipt.sole.outcome
  end

  test 'legacy status cannot undo a completed jump' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    response = TradeService.status(username: @user.username, shard: @shard.channel_uuid, location: @gate.name)
    assert_equal @destination.name, response[:player_location]
    assert_equal @destination.name, response.dig(:ship, :location)
    assert_equal 'ignored', response.dig(:location_sync, :status)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
  end

  test 'location free status leaves completed state unchanged' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    response = report(nil)
    assert_equal @destination.name, response[:player_location]
    refute response.key?(:location_sync)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
    TradeService.status(username: @user.username, shard: @shard.channel_uuid)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
  end

  test 'a fresh return journey remains possible after rejecting stale status' do
    complete_gate
    report(@gate.name)
    returning = GateTravelService.new(ship_guid: @hull.guid, travel_guid: 'guarded-return').call
    assert_equal @destination, returning.origin_location
    assert_equal @gate, returning.arrival_location
    ShipTravelArrivalProcessor.new(travel: returning.travel, current_tick: returning.travel.arrival_tick).call
    assert_equal @gate.name, @hull.reload.location_name
    assert_equal @gate.name, @player.reload.current_location_name
    assert_equal 2, TravelRequestReceipt.where(outcome: 'completed').count
  end

  test 'pre-travel status initialization and existing external relocation remain supported' do
    response = report(@destination.name)
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal @destination.name, @player.reload.current_location_name
    refute response.key?(:location_sync)
    assert_empty TravelRequestReceipt.all
  end

  test 'completed receipt protection does not expire' do
    complete_gate
    TravelRequestReceipt.sole.update_columns(created_at: 2.years.ago, updated_at: 2.years.ago)
    report(@gate.name)
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal @destination.name, @player.reload.current_location_name
  end

  test 'historical valid interdiction and mismatched player stay byte for byte unchanged' do
    travel = saved_trip
    travel.interdict!(95)
    @player.update_current_location!(@destination)
    before = [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes, assets]
    response = report(@origin.name)
    assert_equal before, [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes, assets]
    assert_equal 'interdicted', response.dig(:ship, :travel_state)
    assert_equal 0, travel.arrival_tick
    assert_equal ['player'], response.dig(:location_sync, :ignored_for)
    assert_empty TravelRequestReceipt.all
  end

  test 'status for another ship cannot relocate the player of a paused journey' do
    travel = saved_trip
    travel.interdict!(95)
    other = UserShip.create!(user: @user, ship: @catalog_ship, shard: @shard, shard_user: @player,
      guid: 'another-hull', location_name: @origin.name, total_scu: 20, used_scu: 0)
    before = [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes]
    response = TradeService.status(ship_guid: other.guid, ship_model: @catalog_ship.model,
      shard_uuid: @shard.channel_uuid, player_guid: @user.uid, player_name: @user.username, location: @destination.name)
    assert_equal before, [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes]
    assert_equal @destination.name, other.reload.location_name
    assert_equal @origin.name, response[:player_location]
    assert_equal ['player'], response.dig(:location_sync, :ignored_for)
  end

  test 'new ship initialization cannot bypass the saved player location' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes]
    response = TradeService.status(ship_guid: 'fresh-hull', ship_model: @catalog_ship.model,
      shard_uuid: @shard.channel_uuid, player_guid: @user.uid, player_name: @user.username, location: @origin.name)
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes]
    assert_equal @origin.name, response.dig(:ship, :location)
    assert_equal @destination.name, response[:player_location]
    assert_equal ['player'], response.dig(:location_sync, :ignored_for)
  end

  test 'status cannot reassign travel managed ship identity to evade location protection' do
    complete_gate
    before = [@hull.reload.attributes, @player.reload.attributes,
      User.count, Shard.count, ShardUser.count, Ship.count]
    error = assert_raises(TravelLifecycle::Error) do
      TradeService.status(ship_guid: @hull.guid, ship_model: 'Unrelated model',
        shard_uuid: 'unrelated-shard', player_guid: 'unrelated-user', player_name: 'Unrelated pilot',
        location: @origin.name)
    end
    assert_equal 'status_identity_conflict', error.code
    assert_equal before, [@hull.reload.attributes, @player.reload.attributes,
      User.count, Shard.count, ShardUser.count, Ship.count]
  end

  test 'pending ordinary journey blocks status movement before completion' do
    travel = saved_trip
    before = [travel.attributes, @hull.reload.attributes, @player.reload.attributes]
    response = report(@destination.name)
    assert_equal before, [travel.reload.attributes, @hull.reload.attributes, @player.reload.attributes]
    assert_equal %w[ship player], response.dig(:location_sync, :ignored_for)
  end

  test 'canonical wallet updates remain independent of a rejected location report' do
    complete_gate
    response = report(@gate.name, wallet_balance: 12_345)
    assert_equal 12_345, response[:wallet_balance]
    assert_equal 12_345, @player.reload.wallet_balance
    assert_equal @destination.name, @player.current_location_name
    assert_equal @destination.name, @hull.reload.location_name
  end
end
