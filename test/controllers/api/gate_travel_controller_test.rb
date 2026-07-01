require "test_helper"

class Api::GateTravelControllerTest < ActionDispatch::IntegrationTest
  setup do
    StarBitizenRun.delete_all
    ShipTravel.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all

    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")

    @origin_gateway = Location.create!(
      name: "Pyro Gateway",
      classification: "space_station",
      star_system_name: "Stanton"
    )
    @destination_gateway = Location.create!(
      name: "Stanton Gateway",
      classification: "space_station",
      star_system_name: "Pyro"
    )
    @non_gateway = Location.create!(
      name: "Orison",
      classification: "city",
      star_system_name: "Stanton"
    )

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-guid")
    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @other_user = User.create!(
      username: "OtherPilot",
      twitch_id: "other-pilot-twitch",
      uid: "other-pilot-guid",
      user_type: "player"
    )
    @shard_user = ShardUser.create!(
      user: @user,
      shard: @shard,
      shard_name: @shard.name,
      wallet_balance: 10_000
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @other_ship = Ship.create!(model: "MISC Freelancer", slug: "misc-freelancer", scu: 66, speed: 90)
    @user_ship = create_user_ship(
      user: @user,
      ship: @ship,
      guid: "target-ship-guid",
      location_name: @origin_gateway.name
    )
    @recent_user_ship = create_user_ship(
      user: @user,
      ship: @other_ship,
      guid: "recent-ship-guid",
      location_name: @non_gateway.name
    )
    @recent_user_ship.touch
  end

  test "valid request with secret_guid and ship_guid moves the correct user ship" do
    post "/api/gate_travel", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_equal @destination_gateway.name, response_json["new_location"]
    assert_equal "You have traveled through the Jumpgate to #{@destination_gateway.name}.", response_json["message"]
    assert_equal @destination_gateway.name, @user_ship.reload.location_name
  end

  test "endpoint no longer requires or uses username" do
    post "/api/gate_travel", params: {
      username: @other_user.username,
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal @destination_gateway.name, @user_ship.reload.location_name
  end

  test "endpoint does not select the most recently updated ship" do
    post "/api/gate_travel", params: {
      username: @user.username,
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal @destination_gateway.name, @user_ship.reload.location_name
    assert_equal @non_gateway.name, @recent_user_ship.reload.location_name
  end

  test "invalid secret_guid returns unauthorized" do
    post "/api/gate_travel", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "wrong-secret"
    }, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "missing secret_guid returns unauthorized" do
    post "/api/gate_travel", params: {
      ship_guid: @user_ship.guid
    }, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "missing ship_guid returns a JSON error" do
    post "/api/gate_travel", params: {
      secret_guid: "test-secret"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "status" => "error", "message" => "ship_guid is required" }, response_json)
  end

  test "unknown ship_guid returns a JSON error" do
    post "/api/gate_travel", params: {
      ship_guid: "missing-ship-guid",
      secret_guid: "test-secret"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "No user ship found for ship_guid missing-ship-guid" },
      response_json
    )
  end

  test "ship not at a gateway returns the expected error" do
    @user_ship.update!(location_name: @non_gateway.name)

    post "/api/gate_travel", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "You are not at a valid Jumpgate location." },
      response_json
    )
  end

  test "located user ship has valid user ship and shard relationships" do
    located_ship = UserShip.includes(:user, :ship, :shard, :shard_user).find_by!(guid: @user_ship.guid)

    assert_equal @user, located_ship.user
    assert_equal @ship, located_ship.ship
    assert_equal @shard, located_ship.shard
    assert_equal @shard_user, located_ship.shard_user
    assert_equal @shard, located_ship.shard_user.shard
    assert_includes @shard.user_ships, located_ship
  end

  private

  def create_user_ship(user:, ship:, guid:, location_name:)
    UserShip.create!(
      user: user,
      ship: ship,
      shard: @shard,
      shard_user: @shard_user,
      shard_name: @shard.name,
      guid: guid,
      ship_slug: ship.slug,
      location_name: location_name,
      total_scu: ship.scu,
      used_scu: 0
    )
  end

  def response_json
    JSON.parse(response.body)
  end
end
