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
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")
    Setting.create!(key: "seconds_per_tick", value: "30", setting_type: "text")
    Setting.create!(key: "interdiction_window_percent", value: "50", setting_type: "text")

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 10)
    end

    @origin_gateway = Location.create!(
      name: "Pyro Gateway (Stanton)",
      nickname: "Pyro Gateway (Stanton)",
      space_station_name: "Pyro Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
    )
    @arrival_gateway = Location.create!(
      name: "Stanton Gateway (Pyro)",
      nickname: "Stanton Gateway (Pyro)",
      space_station_name: "Stanton Gateway (Pyro)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )
    @wrong_system_gateway = Location.create!(
      name: "Stanton Gateway (Terra)",
      classification: "space_station",
      star_system_name: "Terra"
    )
    @suffix_origin_gateway = Location.create!(
      name: "Magnus Gateway (Stanton)",
      nickname: "Magnus Gateway (Stanton)",
      space_station_name: "Magnus Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
    )
    @suffix_arrival_gateway = Location.create!(
      name: "Stanton Gateway (Magnus)",
      nickname: "Stanton Gateway (Magnus)",
      space_station_name: "Stanton Gateway (Magnus)",
      classification: "space_station",
      star_system_name: "Magnus",
      is_available: true,
      is_visible: true
    )
    @pyro_location = Location.create!(
      name: "Ruin Station",
      classification: "space_station",
      star_system_name: "Pyro"
    )
    @nyx_gateway_in_pyro = Location.create!(
      name: "Nyx Gateway (Pyro)",
      nickname: "Nyx Gateway (Pyro)",
      space_station_name: "Nyx Gateway (Pyro)",
      orbit_name: "Nyx Gateway (Pyro system)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )
    @pyro_gateway_in_nyx = Location.create!(
      name: "Pyro Gateway (Nyx)",
      nickname: "Pyro Gateway (Nyx)",
      space_station_name: "Pyro Gateway (Nyx)",
      classification: "space_station",
      star_system_name: "Nyx",
      is_available: true,
      is_visible: true
    )
    @nyx_gateway_in_stanton = Location.create!(
      name: "Nyx Gateway (Stanton)",
      nickname: "Nyx Gateway (Stanton)",
      space_station_name: "Nyx Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
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

  test "valid request starts a pending two minute gate travel for the correct user ship" do
    post_gate_travel(ship_guid: @user_ship.guid)

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_equal "Gate travel initiated. Arrival pending.", response_json["message"]
    assert_equal 120, response_json["travel_time_seconds"]
    assert_equal 10, response_json["current_tick"]
    assert_equal 14, response_json["arrival_tick"]
    assert_equal 120, response_json["time_remaining"]
    assert_equal @origin_gateway.name, response_json["origin_location"]
    assert_equal "Stanton", response_json["origin_star_system"]
    assert_equal @arrival_gateway.name, response_json["arrival_location"]
    assert_equal "Pyro", response_json["arrival_star_system"]
    assert_equal @arrival_gateway.name, response_json["new_location"]

    travel = ShipTravel.find_by!(travel_guid: response_json["travel_guid"])
    assert_equal @user_ship, travel.user_ship
    assert_equal @origin_gateway, travel.from_location
    assert_equal @arrival_gateway, travel.to_location
    assert_equal "gate_travel", travel.ship_travel_type
    assert_equal 4, travel.total_duration_ticks
    assert_nil travel.completed_at_tick
    assert_equal @origin_gateway.name, @user_ship.reload.location_name
    assert_equal "in_transit", @user_ship.status
  end

  test "ship at Pyro Gateway in Stanton resolves target star system Pyro and arrival Stanton Gateway in Pyro" do
    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Pyro Gateway")

    assert_response :success
    assert_equal "Pyro", response_json["arrival_star_system"]
    assert_equal @arrival_gateway.name, response_json["arrival_location"]
    assert_equal @arrival_gateway, ShipTravel.find_by!(travel_guid: response_json["travel_guid"]).to_location
  end

  test "ship in Pyro can enter Nyx Gateway without parenthetical suffix" do
    @user_ship.update!(location_name: @pyro_location.name)

    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Nyx Gateway")

    assert_response :success
    assert_equal @nyx_gateway_in_pyro.name, response_json["origin_location"]
    assert_equal "Pyro", response_json["origin_star_system"]
    assert_equal "Nyx", response_json["arrival_star_system"]
    assert_equal @pyro_gateway_in_nyx.name, response_json["arrival_location"]
    assert_equal @nyx_gateway_in_pyro.name, @user_ship.reload.location_name

    travel = ShipTravel.find_by!(travel_guid: response_json["travel_guid"])
    assert_equal @nyx_gateway_in_pyro, travel.from_location
    assert_equal @pyro_gateway_in_nyx, travel.to_location
  end

  test "ship in Pyro can enter Stanton Gateway without parenthetical suffix" do
    @user_ship.update!(location_name: @pyro_location.name)

    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Stanton Gateway")

    assert_response :success
    assert_equal @arrival_gateway.name, response_json["origin_location"]
    assert_equal @origin_gateway.name, response_json["arrival_location"]
  end

  test "full parenthetical gateway form still works" do
    @user_ship.update!(location_name: @pyro_location.name)

    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Nyx Gateway (Pyro)")

    assert_response :success
    assert_equal @nyx_gateway_in_pyro.name, response_json["origin_location"]
    assert_equal @pyro_gateway_in_nyx.name, response_json["arrival_location"]
  end

  test "arrival lookup scopes by star_system_name instead of selecting a same-label gateway in another system" do
    post_gate_travel(ship_guid: @user_ship.guid)

    assert_response :success
    travel = ShipTravel.find_by!(travel_guid: response_json["travel_guid"])
    assert_equal @arrival_gateway, travel.to_location
    refute_equal @wrong_system_gateway, travel.to_location
  end

  test "gateway name works without parenthetical suffix" do
    @user_ship.update!(location_name: @suffix_origin_gateway.name)

    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Magnus Gateway")

    assert_response :success
    assert_equal "Magnus", response_json["arrival_star_system"]
    assert_equal @suffix_arrival_gateway.name, response_json["arrival_location"]
  end

  test "invalid gateway name returns a useful JSON error" do
    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Terra Gateway")

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Gateway Terra Gateway is not available from Stanton." },
      response_json
    )
  end

  test "unqualified gateway lookup selects the match in the current star system" do
    @user_ship.update!(location_name: @pyro_location.name)

    post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Nyx Gateway")

    assert_response :success
    assert_equal @nyx_gateway_in_pyro.name, response_json["origin_location"]
    refute_equal @nyx_gateway_in_stanton.name, response_json["origin_location"]
  end

  test "ambiguous destination gateway data returns a useful JSON error" do
    Location.create!(
      name: "Stanton Gateway (Pyro)",
      classification: "space_station",
      star_system_name: "Pyro"
    )

    post_gate_travel(ship_guid: @user_ship.guid)

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Multiple destination Jumpgates match Stanton Gateway in Pyro." },
      response_json
    )
  end

  test "endpoint no longer requires or uses username" do
    post_gate_travel(ship_guid: @user_ship.guid, username: @other_user.username)

    assert_response :success
    assert_equal @origin_gateway.name, @user_ship.reload.location_name
    assert_equal @arrival_gateway, ShipTravel.last.to_location
  end

  test "endpoint does not select the most recently updated ship" do
    post_gate_travel(ship_guid: @user_ship.guid, username: @user.username)

    assert_response :success
    assert_equal @origin_gateway.name, @user_ship.reload.location_name
    assert_equal @non_gateway.name, @recent_user_ship.reload.location_name
    assert_equal @user_ship, ShipTravel.last.user_ship
  end

  test "invalid secret_guid returns unauthorized" do
    post_gate_travel(ship_guid: @user_ship.guid, secret_guid: "wrong-secret")

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "missing secret_guid returns unauthorized" do
    post "/api/gate_travel", params: { ship_guid: @user_ship.guid }, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "missing ship_guid returns a JSON error" do
    post_gate_travel(ship_guid: nil)

    assert_response :unprocessable_entity
    assert_equal({ "status" => "error", "message" => "ship_guid is required" }, response_json)
  end

  test "unknown ship_guid returns a JSON error" do
    post_gate_travel(ship_guid: "missing-ship-guid")

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "No user ship found for ship_guid missing-ship-guid" },
      response_json
    )
  end

  test "ship not at a gateway returns the expected error" do
    @user_ship.update!(location_name: @non_gateway.name)

    post_gate_travel(ship_guid: @user_ship.guid)

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "You are not at a valid Jumpgate location." },
      response_json
    )
  end

  test "ship arrives after the two minute gate travel delay using the normal arrival job" do
    post_gate_travel(ship_guid: @user_ship.guid)
    travel = ShipTravel.find_by!(travel_guid: response_json["travel_guid"])

    assert_equal @origin_gateway.name, @user_ship.reload.location_name

    Tick.instance.update_columns(current_tick: travel.arrival_tick, sequence: travel.arrival_tick)
    sent_reports = 0

    RabbitmqSender.stub(:send_ship_report, ->(_travel) { sent_reports += 1 }) do
      ShipArrivalJob.perform_now
    end

    refute ShipTravel.exists?(travel.id)
    assert_equal @arrival_gateway.name, @user_ship.reload.location_name
    assert_equal "docked", @user_ship.status
    assert_equal 1, sent_reports
  end

  test "normal travel service still creates calculated travel records" do
    normal_destination = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
    normal_ship = create_user_ship(
      user: @user,
      ship: @ship,
      guid: "normal-travel-ship-guid",
      location_name: @non_gateway.name
    )

    travel = TravelService.new(
      user_ship: normal_ship,
      to_location: normal_destination,
      travel_guid: "normal-travel-guid"
    ).call

    assert_equal normal_ship, travel.user_ship
    assert_nil travel.ship_travel_type
    assert_equal "in_transit", normal_ship.reload.status
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

  def post_gate_travel(ship_guid:, secret_guid: "test-secret", username: nil, gateway_name: nil)
    params = {
      ship_guid: ship_guid,
      secret_guid: secret_guid,
      username: username,
      gateway_name: gateway_name
    }.compact

    post "/api/gate_travel", params: params, as: :json
  end

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
