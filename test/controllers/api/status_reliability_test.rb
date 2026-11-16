require "test_helper"
require "minitest/mock"

# M04 — status reliability: payload path selection (F-19), bounded retries
# (F-17), normalized shard identity (F-04 / Q3).
class Api::StatusReliabilityTest < ActionDispatch::IntegrationTest
  setup do
    [TravelArrivalEvent, TravelRequestReceipt, TravelResumeAction, StarBitizenRun, UserShipCargo,
     ShipTravel, UserShip, ShardUser, User, Ship, Shard, Location, Setting].each(&:delete_all)
    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")
    @shard = Shard.create!(name: "Reliable", region: "us", channel_uuid: "Reliable-UUID")
    @user = User.create!(username: "ReliablePilot", twitch_id: "reliable-twitch", uid: "reliable-uid", user_type: "player")
    @player = ShardUser.create!(user: @user, shard: @shard, wallet_balance: 500)
    @ship = Ship.create!(model: "Reliable Hull", slug: "reliable-hull", scu: 4)
    @hull = UserShip.create!(user: @user, ship: @ship, shard: @shard, shard_user: @player,
      guid: "reliable-ship", total_scu: 4, used_scu: 0)
  end

  test "username plus shard_uuid without ship fields uses the legacy path (F-19)" do
    post "/api/status", params: { username: @user.username, shard_uuid: @shard.channel_uuid,
      secret_guid: "test-secret" }, as: :json
    assert_response :success
    assert_equal "success", response.parsed_body["status"]
    assert_equal @ship.model, response.parsed_body.dig("ship", "model")
  end

  test "a stable player_guid never downgrades to the legacy path (F-19)" do
    post "/api/status", params: { username: @user.username, player_guid: @user.twitch_id,
      shard_uuid: @shard.channel_uuid, secret_guid: "test-secret" }, as: :json
    assert_response :bad_request
    assert_equal "ship_guid is required", response.parsed_body["message"]
  end

  test "status retries a uniqueness race a bounded number of times (F-17)" do
    calls = 0
    raiser = ->(**) { calls += 1; raise ActiveRecord::RecordNotUnique, "simulated race" }
    TradeService.stub(:authoritative_status_sync!, raiser) do
      assert_raises(ActiveRecord::RecordNotUnique) do
        TradeService.status(ship_guid: @hull.guid, ship_model: @ship.model, shard_uuid: @shard.channel_uuid,
          player_guid: @user.twitch_id, player_name: @user.username)
      end
    end
    assert_equal TradeService::MAX_STATUS_ATTEMPTS, calls
  end

  test "shard identity is unique case- and whitespace-insensitively (F-04)" do
    duplicate = Shard.new(name: "Duplicate", region: "us", channel_uuid: " reliable-uuid ")
    refute duplicate.valid?
    assert_includes duplicate.errors[:channel_uuid].join, "matches another shard"

    other = Shard.create!(name: "Other", region: "us", channel_uuid: "other-uuid")
    assert_raises(ActiveRecord::RecordNotUnique) { other.update_columns(channel_uuid: "RELIABLE-uuid") }
  end

  test "travel and trades resolve a case variant of the shard uuid (F-04)" do
    assert_equal @shard, Shard.lookup_channel_uuid("  reliable-UUID ")
    assert_equal @shard, TradeService.find_trade_shard("RELIABLE-uuid")
    assert_nil Shard.lookup_channel_uuid("unknown-uuid")
  end

  test "status responses always carry additive warnings and location_resolution keys" do
    post "/api/status", params: { ship_guid: @hull.guid, ship_model: @ship.model, shard_uuid: @shard.channel_uuid,
      player_guid: @user.twitch_id, player_name: @user.username, secret_guid: "test-secret" }, as: :json
    assert_response :success
    assert_equal [], response.parsed_body["warnings"]
    assert_equal "absent", response.parsed_body["location_resolution"]
    refute_includes response.body, "test-secret"
  end
end
