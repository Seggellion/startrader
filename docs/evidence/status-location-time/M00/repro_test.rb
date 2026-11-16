# M00 pre-fix reproductions for the status/location/time repair.
#
# Evidence-only: this file lives outside test/ so `rails test` never picks it up.
# Run explicitly:
#   CODEX_ENV_FILE=... bin/codex_test docs/evidence/status-location-time/M00/repro_test.rb
#
# Each test asserts the TARGET behaviour. "PREDICTED FAIL" means the discovery (or
# M00 revalidation against c73b582) predicts the production source fails that
# assertion; "PREDICTED PASS" means a v172+ release is believed to have fixed it.
# The observed outcome is recorded in M00/RESULT.md, never edited into this file.
require "test_helper"
require "minitest/mock"

class StatusLocationTimeReproTest < ActionDispatch::IntegrationTest
  setup do
    TravelArrivalEvent.delete_all
    TravelRequestReceipt.delete_all
    TravelResumeAction.delete_all
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all
    Tick.delete_all
    Setting.create!(key: "seconds_per_tick", value: "5", setting_type: "text")
    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")
    MarketPriceUpdater.stub(:update_prices!, nil) { Tick.create!(current_tick: 10, sequence: 10) }

    @shard = Shard.create!(name: "ReproShard", region: "us", channel_uuid: "repro-shard-guid")
    @user = User.create!(username: "ReproPilot", twitch_id: "repro-twitch", uid: "repro-uid", user_type: "player")
    @shard_user = ShardUser.create!(user: @user, shard: @shard, wallet_balance: 10_000)
    @here = Location.create!(name: "Repro Here", classification: "city", star_system_name: "Stanton")
    @there = Location.create!(name: "Repro There", classification: "city", star_system_name: "Stanton")
    @elsewhere = Location.create!(name: "Repro Elsewhere", classification: "city", star_system_name: "Stanton")
    @ship = Ship.create!(model: "Repro Hull", slug: "repro-hull", scu: 8)
    @user_ship = UserShip.create!(user: @user, ship: @ship, shard: @shard, shard_user: @shard_user,
      shard_name: @shard.name, guid: "repro-ship-guid", ship_slug: @ship.slug,
      location_name: @here.name, total_scu: 8, used_scu: 0, status: "docked")
    @shard_user.update_current_location!(@here)
  end

  # R-3 / F-18 — PREDICTED FAIL: unresolvable location returns 400 and nothing else is applied.
  test "R-3 F-18 unresolvable location degrades instead of aborting the sync" do
    post "/api/status", params: payload(location: "Not A Real Place", wallet_balance: 99_999), as: :json
    assert_response :success
    assert_equal 99_999, @shard_user.reload.wallet_balance
    assert_equal @here.name, @shard_user.current_location_name
  end

  # R-4 / F-04 — PREDICTED FAIL: a case-variant shard UUID creates a sibling Shard + ShardUser.
  test "R-4 F-04 case-variant shard uuid matches the existing shard" do
    assert_no_difference ["Shard.count", "ShardUser.count"] do
      post "/api/status", params: payload(shard_uuid: @shard.channel_uuid.upcase), as: :json
    end
  end

  # R-5 / F-05 — PREDICTED FAIL: a case-colliding player_name aborts the whole status request.
  test "R-5 F-05 username collision does not abort location and wallet sync" do
    other = User.create!(username: "Collider", twitch_id: "other-twitch", uid: "other-uid", user_type: "player")
    post "/api/status", params: payload(player_name: "COLLIDER", wallet_balance: 77_777, location: @there.name), as: :json
    assert_response :success
    assert_equal 77_777, @shard_user.reload.wallet_balance
    assert_equal @there.name, @shard_user.current_location_name
    assert_equal "ReproPilot", @user.reload.username
    assert_equal "Collider", other.reload.username
  end

  # R-6 / F-13 — PREDICTED FAIL: the legacy ship block reports 0 remaining for an interdicted journey.
  test "R-6 F-13 interdicted countdown is consistent between ship and travel blocks" do
    travel = ShipTravel.create!(user_ship: @user_ship, from_location: @here, to_location: @there,
      travel_guid: "repro-paused-guid", departure_tick: 5, arrival_tick: 20, total_duration_ticks: 15,
      rabbitmq_environment: "dev")
    travel.interdict!(10)
    @user_ship.update!(status: "interdicted")
    post "/api/status", params: payload, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body.dig("travel", "arrival_tick")
    assert_operator body.dig("travel", "time_remaining").to_i, :>, 0
    assert_equal body.dig("travel", "time_remaining"), body.dig("ship", "time_remaining")
  end

  # N-01 — PREDICTED FAIL: after a completed journey (durable receipt, journey row deleted),
  # an idle status with a valid new location never updates the player or ship again.
  test "N-01 idle status after a completed journey updates last_location again" do
    TravelRequestReceipt.create!(travel_guid: "repro-completed-guid", user_ship_id: @user_ship.id,
      request_context: { kind: "travel" }, travel_snapshot: {}, outcome: "completed", completed_at_tick: 9)
    refute ShipTravel.where(user_ship_id: @user_ship.id).exists?
    post "/api/status", params: payload(location: @there.name), as: :json
    assert_response :success
    assert_equal @there.name, @shard_user.reload.current_location_name
    assert_equal @there.name, @user_ship.reload.location_name
  end

  # R-2 / F-03 — PREDICTED PASS (v173): in-flight conflicting report is ignored, journey untouched.
  test "R-2 F-03 in-flight conflicting location is ignored and the journey is untouched" do
    travel = ShipTravel.create!(user_ship: @user_ship, from_location: @here, to_location: @there,
      travel_guid: "repro-active-guid", departure_tick: 5, arrival_tick: 20, total_duration_ticks: 15,
      rabbitmq_environment: "dev")
    @user_ship.update!(status: "in_transit")
    before = travel.reload.attributes
    post "/api/status", params: payload(location: @elsewhere.name), as: :json
    assert_response :success
    assert_equal @here.name, @shard_user.reload.current_location_name
    assert_equal @here.name, @user_ship.reload.location_name
    assert_equal before, travel.reload.attributes
  end

  private

  def payload(**overrides)
    { ship_guid: @user_ship.guid, ship_model: @ship.model, shard_uuid: @shard.channel_uuid,
      player_guid: @user.twitch_id, player_name: @user.username, secret_guid: "test-secret" }.merge(overrides)
  end
end

# R-1 / F-01 — PREDICTED PASS (v172): a Jump aligns the player at departure and at arrival.
class StatusLocationTimeJumpReproTest < ActiveSupport::TestCase
  require_relative "../../../../test/support/travel_repair_fixtures"
  include TravelRepairFixtures

  setup { setup_travel_repair }
  teardown { cleanup_travel_repair }

  test "R-1 F-01 jump aligns player at departure and arrival" do
    @hull.update!(location_name: @gate.name)
    @player.update_current_location!(@gate)
    travel = GateTravelService.new(ship_guid: @hull.guid, travel_guid: SecureRandom.uuid).call.travel
    assert_equal @gate.name, @player.reload.current_location_name
    assert_equal @gate.name, @hull.reload.location_name
    Tick.instance.update_columns(current_tick: travel.arrival_tick, sequence: travel.arrival_tick)
    ShipTravelArrivalProcessor.new(travel: travel, current_tick: travel.arrival_tick, notify: false).call
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal @destination.name, @player.reload.current_location_name
  end
end
