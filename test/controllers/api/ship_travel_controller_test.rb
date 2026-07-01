require "test_helper"

class Api::ShipTravelControllerTest < ActionDispatch::IntegrationTest
  setup do
    StarBitizenRun.delete_all
    ShipTravel.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all

    Setting.create!(key: "interdiction_window_percent", value: "50", setting_type: "text")
    Setting.create!(key: "seconds_per_tick", value: "30", setting_type: "text")
    Setting.create!(key: "hours_per_tick", value: "1", setting_type: "text")
    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")

    ActiveRecord::Base.connection.execute("DELETE FROM ticks")
    Tick.create!(current_tick: 10, sequence: 1)

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-guid")
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
  end

  test "create rejects a missing travel_guid" do
    post "/api/travel", params: { ship_travel: travel_payload.except(:travel_guid) }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "travel_guid is required." }, response_json)
    assert_equal 0, ShipTravel.count
  end

  test "create rejects a blank travel_guid" do
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: " ") }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "travel_guid is required." }, response_json)
    assert_equal 0, ShipTravel.count
  end

  test "create persists and returns travel_guid" do
    guid = "client-travel-guid-1"

    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json

    assert_response :success
    assert_equal guid, response_json["travel_guid"]
    assert_equal guid, ShipTravel.find_by!(travel_guid: guid).travel_guid
  end

  test "create resolves destination from short facility code" do
    destination = create_shubin_22_location

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-facility-code",
        to_location: "SM0-22"
      )
    }, as: :json

    assert_response :success
    assert_equal destination.name, response_json["destination"]
    assert_equal destination, ShipTravel.find_by!(travel_guid: "client-travel-guid-facility-code").to_location
  end

  test "create resolves destination from nickname-style location" do
    destination = create_shubin_22_location

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-shubin-22",
        to_location: "Shubin 22"
      )
    }, as: :json

    assert_response :success
    assert_equal destination.name, response_json["destination"]
    assert_equal destination, ShipTravel.find_by!(travel_guid: "client-travel-guid-shubin-22").to_location
  end

  test "create resolves unqualified gateway destination within from location star system" do
    stanton_gateway_pyro, nyx_gateway_pyro, _nyx_gateway_stanton = create_gateway_locations

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-nyx-gateway",
        ship_guid: "333-333-333-335",
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal "travel_started", response_json["status"]
    assert_equal nyx_gateway_pyro.name, response_json["destination"]

    travel = ShipTravel.find_by!(travel_guid: "client-travel-guid-nyx-gateway")
    assert_equal stanton_gateway_pyro, travel.from_location
    assert_equal nyx_gateway_pyro, travel.to_location
    assert_equal nyx_gateway_pyro.name, travel.to_location.name
  end

  test "create syncs missing user shard user and user ship from travel payload" do
    stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    caterpillar = Ship.create!(model: "Drake Caterpillar", slug: "caterpillar", scu: 576, speed: 80)

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-cold-sync",
        ship_guid: "333-333-333-335",
        ship_slug: caterpillar.slug,
        player_guid: "136591885",
        player_name: "Seggellion",
        shard_uuid: @shard.channel_uuid,
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal "travel_started", response_json["status"]
    assert_equal nyx_gateway_pyro.name, response_json["destination"]

    user = User.find_by!(twitch_id: "136591885")
    shard_user = ShardUser.find_by!(user: user, shard: @shard)
    user_ship = UserShip.find_by!(guid: "333-333-333-335")
    travel = ShipTravel.find_by!(travel_guid: "client-travel-guid-cold-sync")

    assert_equal "Seggellion", user.username
    assert_equal "136591885", user.uid
    assert_equal @shard.name, shard_user.shard_name
    assert_equal user, user_ship.user
    assert_equal @shard, user_ship.shard
    assert_equal shard_user, user_ship.shard_user
    assert_equal caterpillar, user_ship.ship
    assert_equal caterpillar.slug, user_ship.ship_slug
    assert_equal 576, user_ship.total_scu
    assert_equal 0, user_ship.used_scu
    assert_equal stanton_gateway_pyro.name, user_ship.location_name
    assert_equal "in_transit", user_ship.status
    assert_equal user_ship, travel.user_ship
    assert_equal stanton_gateway_pyro, travel.from_location
    assert_equal nyx_gateway_pyro, travel.to_location
  end

  test "create updates existing player username and creates missing shard user" do
    stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    user = User.create!(
      username: "OldPilotName",
      twitch_id: "rename-player-guid",
      uid: "rename-player-guid",
      user_type: "player"
    )

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-rename-sync",
        ship_guid: "rename-sync-ship-guid",
        player_guid: user.twitch_id,
        player_name: "NewPilotName",
        from_location: stanton_gateway_pyro.name,
        to_location: nyx_gateway_pyro.name
      )
    }, as: :json

    assert_response :success
    assert_equal "NewPilotName", user.reload.username
    assert ShardUser.exists?(user: user, shard: @shard)
  end

  test "create does not silently steal a user ship from another player" do
    stanton_gateway_pyro, _nyx_gateway_pyro, = create_gateway_locations
    owner = User.create!(
      username: "OwnerPilot",
      twitch_id: "owner-player-guid",
      uid: "owner-player-guid",
      user_type: "player"
    )
    owner_shard_user = ShardUser.create!(user: owner, shard: @shard, shard_name: @shard.name)
    UserShip.create!(
      user: owner,
      ship: @ship,
      shard: @shard,
      shard_user: owner_shard_user,
      shard_name: @shard.name,
      guid: "owned-by-someone-else",
      ship_slug: @ship.slug,
      location: stanton_gateway_pyro,
      total_scu: @ship.scu,
      used_scu: 0
    )

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-ship-theft",
        ship_guid: "owned-by-someone-else",
        player_guid: "requesting-player-guid",
        player_name: "RequestingPilot",
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Ship does not belong to this player" }, response_json)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-ship-theft")
  end

  test "create does not silently use a user ship from another shard" do
    stanton_gateway_pyro, _nyx_gateway_pyro, = create_gateway_locations
    other_shard = Shard.create!(name: "OtherShard", region: "us", channel_uuid: "other-shard-guid")
    user = User.create!(
      username: "ShardMismatchPilot",
      twitch_id: "shard-mismatch-player-guid",
      uid: "shard-mismatch-player-guid",
      user_type: "player"
    )
    other_shard_user = ShardUser.create!(user: user, shard: other_shard, shard_name: other_shard.name)
    UserShip.create!(
      user: user,
      ship: @ship,
      shard: other_shard,
      shard_user: other_shard_user,
      shard_name: other_shard.name,
      guid: "wrong-shard-ship-guid",
      ship_slug: @ship.slug,
      location: stanton_gateway_pyro,
      total_scu: @ship.scu,
      used_scu: 0
    )

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-wrong-shard",
        ship_guid: "wrong-shard-ship-guid",
        player_guid: user.twitch_id,
        player_name: user.username,
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Ship does not belong to this shard" }, response_json)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-wrong-shard")
  end

  test "create accepts full parenthetical gateway destination" do
    stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-nyx-gateway-full",
        ship_guid: "333-333-333-336",
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway (Pyro)"
      )
    }, as: :json

    assert_response :success
    assert_equal nyx_gateway_pyro.name, response_json["destination"]
    assert_equal nyx_gateway_pyro, ShipTravel.find_by!(travel_guid: "client-travel-guid-nyx-gateway-full").to_location
  end

  test "create scopes unqualified gateway destination to current system" do
    stanton_gateway_pyro, nyx_gateway_pyro, nyx_gateway_stanton = create_gateway_locations

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-scoped-nyx-gateway",
        ship_guid: "333-333-333-337",
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :success
    travel = ShipTravel.find_by!(travel_guid: "client-travel-guid-scoped-nyx-gateway")
    assert_equal nyx_gateway_pyro, travel.to_location
    refute_equal nyx_gateway_stanton, travel.to_location
  end

  test "create accepts unqualified from location matching existing current gateway" do
    _stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    terra_gateway_pyro = create_gateway("Terra Gateway (Pyro)", "Pyro")
    create_gateway("Terra Gateway (Stanton)", "Stanton")
    user_ship = create_existing_synced_ship_at(nyx_gateway_pyro, guid: "nyx-current-ship-guid")

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-unqualified-from",
        ship_guid: user_ship.guid,
        player_guid: user_ship.user.twitch_id,
        player_name: user_ship.user.username,
        from_location: "Nyx Gateway",
        to_location: "terra gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal "travel_started", response_json["status"]
    assert_equal terra_gateway_pyro.name, response_json["destination"]

    travel = ShipTravel.find_by!(travel_guid: "client-travel-guid-unqualified-from")
    assert_equal nyx_gateway_pyro, travel.from_location
    assert_equal terra_gateway_pyro, travel.to_location
  end

  test "create accepts lowercase from location matching existing current gateway" do
    _stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    terra_gateway_pyro = create_gateway("Terra Gateway (Pyro)", "Pyro")
    user_ship = create_existing_synced_ship_at(nyx_gateway_pyro, guid: "lowercase-from-ship-guid")

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-lowercase-from",
        ship_guid: user_ship.guid,
        player_guid: user_ship.user.twitch_id,
        player_name: user_ship.user.username,
        from_location: "nyx gateway",
        to_location: "terra gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal terra_gateway_pyro.name, response_json["destination"]
  end

  test "create accepts full parenthetical from location matching existing current gateway" do
    _stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    terra_gateway_pyro = create_gateway("Terra Gateway (Pyro)", "Pyro")
    user_ship = create_existing_synced_ship_at(nyx_gateway_pyro, guid: "full-from-ship-guid")

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-full-from",
        ship_guid: user_ship.guid,
        player_guid: user_ship.user.twitch_id,
        player_name: user_ship.user.username,
        from_location: "Nyx Gateway (Pyro)",
        to_location: "Terra Gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal terra_gateway_pyro.name, response_json["destination"]
  end

  test "create rejects truly different from location after scoped resolution" do
    stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    create_gateway("Terra Gateway (Pyro)", "Pyro")
    user_ship = create_existing_synced_ship_at(nyx_gateway_pyro, guid: "different-from-ship-guid")

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-different-from",
        ship_guid: user_ship.guid,
        player_guid: user_ship.user.twitch_id,
        player_name: user_ship.user.username,
        from_location: "Stanton Gateway",
        to_location: "Terra Gateway"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "from_location does not match current ship location." }, response_json)
    assert_equal stanton_gateway_pyro, Location.find_by!(name: stanton_gateway_pyro.name)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-different-from")
  end

  test "create rejects ambiguous unqualified from location when ship has no current location" do
    create_gateway_locations
    Ship.create!(model: "Drake Caterpillar", slug: "caterpillar", scu: 576, speed: 80)

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-ambiguous-from",
        ship_guid: "ambiguous-from-ship-guid",
        ship_slug: "caterpillar",
        player_guid: "ambiguous-from-player-guid",
        player_name: "AmbiguousPilot",
        from_location: "Nyx Gateway",
        to_location: "Terra Gateway"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "from_location is ambiguous without a current ship location." }, response_json)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-ambiguous-from")
  end

  test "create uses existing ship location star system for destination resolution" do
    stanton_gateway_pyro, nyx_gateway_pyro, = create_gateway_locations
    user = User.create!(
      username: "ExistingPilot",
      twitch_id: "existing-pilot-twitch",
      uid: "existing-pilot-guid",
      user_type: "player"
    )
    shard_user = ShardUser.create!(user: user, shard: @shard, shard_name: @shard.name)
    user_ship = UserShip.create!(
      user: user,
      ship: @ship,
      shard: @shard,
      shard_user: shard_user,
      shard_name: @shard.name,
      guid: "existing-location-ship-guid",
      ship_slug: @ship.slug,
      location: stanton_gateway_pyro,
      total_scu: @ship.scu,
      used_scu: 0
    )

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-existing-location",
        ship_guid: user_ship.guid,
        player_guid: user.uid,
        player_name: user.username,
        from_location: nil,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :success
    assert_equal nyx_gateway_pyro.name, response_json["destination"]
  end

  test "create returns explicit error when request from location conflicts with server location" do
    stanton_gateway_pyro, _nyx_gateway_pyro, = create_gateway_locations
    user = User.create!(
      username: "MismatchPilot",
      twitch_id: "mismatch-pilot-twitch",
      uid: "mismatch-pilot-guid",
      user_type: "player"
    )
    shard_user = ShardUser.create!(user: user, shard: @shard, shard_name: @shard.name)
    user_ship = UserShip.create!(
      user: user,
      ship: @ship,
      shard: @shard,
      shard_user: shard_user,
      shard_name: @shard.name,
      guid: "mismatch-location-ship-guid",
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0
    )

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-location-mismatch",
        ship_guid: user_ship.guid,
        player_guid: user.uid,
        player_name: user.username,
        from_location: stanton_gateway_pyro.name,
        to_location: "Nyx Gateway"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "from_location does not match current ship location." }, response_json)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-location-mismatch")
  end

  test "create still rejects exact destinations outside the current star system" do
    stanton_gateway_pyro, _nyx_gateway_pyro, nyx_gateway_stanton = create_gateway_locations

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: "client-travel-guid-cross-system-gateway",
        ship_guid: "333-333-333-338",
        from_location: stanton_gateway_pyro.name,
        to_location: nyx_gateway_stanton.name
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "You cannot travel outside your current star system." }, response_json)
    assert_nil ShipTravel.find_by(travel_guid: "client-travel-guid-cross-system-gateway")
  end

  test "location response includes travel_guid while in transit" do
    guid = "client-travel-guid-2"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    user_ship_id = response_json["user_ship_id"]

    get "/api/location/#{user_ship_id}"

    assert_response :success
    assert_equal true, response_json["in_transit"]
    assert_equal guid, response_json["travel_guid"]
  end

  test "arrival response includes the original travel_guid and is idempotent" do
    guid = "client-travel-guid-3"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    travel = ShipTravel.find_by!(travel_guid: guid)
    Tick.instance.update_columns(current_tick: travel.arrival_tick, sequence: travel.arrival_tick)

    sent_reports = 0
    RabbitmqSender.stub(:send_ship_report, ->(_travel) { sent_reports += 1 }) do
      get "/api/location/#{travel.user_ship_id}"
      assert_response :success
      assert_equal false, response_json["in_transit"]
      assert_equal true, response_json["arrived"]
      assert_equal @to_location.name, response_json["location"]
      assert_equal guid, response_json["travel_guid"]

      get "/api/location/#{travel.user_ship_id}"
      assert_response :success
      assert_equal guid, response_json["travel_guid"]
    end

    assert_equal 1, sent_reports
    assert_equal travel.arrival_tick, travel.reload.completed_at_tick
  end

  test "interdicted paused and resumed travel preserves travel_guid" do
    guid = "client-travel-guid-4"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    travel = ShipTravel.find_by!(travel_guid: guid)

    post "/api/user_ships/#{travel.user_ship.guid}/interdict"
    assert_response :success
    assert_equal guid, response_json["travel_guid"]
    assert_equal [], response_json["user_ship_cargo"]

    get "/api/location/#{travel.user_ship_id}"
    assert_response :success
    assert_equal false, response_json["in_transit"]
    assert_equal true, response_json["paused"]
    assert_equal guid, response_json["travel_guid"]

    post "/api/user_ships/#{travel.user_ship.guid}/resume"
    assert_response :success
    assert_equal guid, response_json["travel_guid"]
    assert_equal guid, travel.reload.travel_guid
  end

  test "interdict by guid includes user ship cargo in the existing cargo JSON shape" do
    guid = "client-travel-guid-with-cargo"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    travel = ShipTravel.find_by!(travel_guid: guid)
    commodity = Commodity.create!(name: "Agricium", is_sellable: true)
    UserShipCargo.create!(
      user_ship: travel.user_ship,
      commodity: commodity,
      commodity_name: commodity.name,
      scu: 2,
      buy_price: 27.50
    )

    expected_cargo = TradeService.user_ship_cargo_json(travel.user_ship).as_json

    post "/api/user_ships/#{travel.user_ship.guid}/interdict"

    assert_response :success
    assert_equal "interdicted", response_json["status"]
    assert_equal guid, response_json["travel_guid"]
    assert_equal expected_cargo, response_json["user_ship_cargo"]
    assert_equal [{ "commodity_name" => "Agricium", "scu" => 2 }], response_json["user_ship_cargo"]
    response_json["user_ship_cargo"].each do |cargo|
      refute_includes cargo.keys, "id"
      refute_includes cargo.keys, "commodity_id"
      refute_includes cargo.keys, "created_at"
      refute_includes cargo.keys, "updated_at"
    end
  end

  test "interdict by guid returns an empty cargo array when the ship has no cargo" do
    guid = "client-travel-guid-empty-cargo"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    travel = ShipTravel.find_by!(travel_guid: guid)

    post "/api/user_ships/#{travel.user_ship.guid}/interdict"

    assert_response :success
    assert_equal "interdicted", response_json["status"]
    assert_equal guid, response_json["travel_guid"]
    assert_equal [], response_json["user_ship_cargo"]
  end

  test "interdictable index returns the client-facing response shape" do
    user = User.create!(
      username: "Seggellion",
      twitch_id: "seggellion-twitch",
      uid: "seggellion-guid",
      user_type: "player"
    )
    user_ship = UserShip.create!(
      user: user,
      ship: @ship,
      shard: @shard,
      shard_name: @shard.name,
      guid: "ship-guid-for-interdictable",
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "in_transit"
    )
    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: "travel-guid-for-interdictable",
      departure_tick: 8,
      arrival_tick: 10,
      total_duration_ticks: 2,
      interdict_window_percent: 50
    )

    get "/api/interdictable_ships"

    assert_response :success
    assert_equal 10, response_json["current_tick"]
    assert_equal 1, response_json["count"]
    assert_kind_of Array, response_json["ships"]

    ship = response_json["ships"].first
    expected_keys = %w[
      travel_guid ship_guid ship_model player_name shard_name shard_uuid
      from_location to_location phase departure_tick arrival_tick total_duration
      windows ticks_to_arrival progress
    ]
    assert_equal expected_keys.sort, ship.keys.sort

    assert_equal "travel-guid-for-interdictable", ship["travel_guid"]
    assert_equal "ship-guid-for-interdictable", ship["ship_guid"]
    assert_equal @ship.model, ship["ship_model"]
    assert_equal "Seggellion", ship["player_name"]
    assert_equal @shard.name, ship["shard_name"]
    assert_equal @shard.channel_uuid, ship["shard_uuid"]
    assert_equal @from_location.name, ship["from_location"]
    assert_equal @to_location.name, ship["to_location"]
    assert_equal "arrival", ship["phase"]
    assert_equal 8, ship["departure_tick"]
    assert_equal 10, ship["arrival_tick"]
    assert_equal 2, ship["total_duration"]
    assert_equal [8, 8], ship.dig("windows", "departure")
    assert_equal [10, 10], ship.dig("windows", "arrival")
    assert_equal 0, ship["ticks_to_arrival"]
    assert_equal 1.0, ship["progress"]

    %w[ship_travel_id ship_name player shard from to window_percent].each do |removed_key|
      refute_includes ship, removed_key
    end
  end

  test "duplicate travel_guid is rejected" do
    guid = "client-travel-guid-5"
    post "/api/travel", params: { ship_travel: travel_payload(travel_guid: guid) }, as: :json
    assert_response :success

    post "/api/travel", params: {
      ship_travel: travel_payload(
        travel_guid: guid,
        ship_guid: "second-ship-guid",
        player_guid: "second-player-guid",
        player_name: "SecondPilot"
      )
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes response_json["error"], "Travel guid has already been taken"
    assert_equal 1, ShipTravel.where(travel_guid: guid).count
  end

  test "cancel rejects request with no secret guid" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    delete "/api/cancel", params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid), as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
    assert_equal 1, ShipTravel.count
  end

  test "cancel rejects request with invalid secret guid" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    delete "/api/cancel",
      params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid),
      headers: { "X-Secret-Guid" => "wrong-secret" },
      as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
    assert_equal 1, ShipTravel.count
  end

  test "cancel succeeds with valid secret guid header" do
    user = create_cancel_user
    user_ship, travel = create_active_cancel_travel(user: user)

    assert_difference "ShipTravel.count", -1 do
      delete "/api/cancel",
        params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid),
        headers: { "X-Secret-Guid" => "test-secret" },
        as: :json
    end

    assert_response :success
    assert_equal "travel_cancelled", response_json["status"]
    assert_equal user_ship.id, response_json["user_ship_id"]
    assert_equal user_ship.guid, response_json["ship_guid"]
    assert_equal travel.travel_guid, response_json["travel_guid"]
    assert_equal @shard.channel_uuid, response_json["channel_uuid"]
    assert_equal "Floating aimlessly in space", user_ship.reload.status
  end

  test "cancel succeeds with valid secret guid param" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    assert_difference "ShipTravel.count", -1 do
      delete "/api/cancel",
        params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid, secret_guid: "test-secret"),
        as: :json
    end

    assert_response :success
    assert_equal "travel_cancelled", response_json["status"]
  end

  test "cancel requires shard uuid" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    delete "/api/cancel",
      params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid).except(:shard_uuid),
      headers: { "X-Secret-Guid" => "test-secret" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "shard_uuid is required." }, response_json)
    assert_equal 1, ShipTravel.count
  end

  test "cancel does not accept legacy shard name matching" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    delete "/api/cancel",
      params: {
        player_guid: user.uid,
        ship_guid: user_ship.guid,
        shard: @shard.name
      },
      headers: { "X-Secret-Guid" => "test-secret" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "shard_uuid is required." }, response_json)
    assert_equal 1, ShipTravel.count
  end

  test "cancel resolves shard by channel uuid" do
    user = create_cancel_user
    user_ship, _travel = create_active_cancel_travel(user: user)

    delete "/api/cancel",
      params: cancel_payload(player_guid: user.uid, ship_guid: user_ship.guid, shard_uuid: @shard.channel_uuid),
      headers: { "X-Secret-Guid" => "test-secret" },
      as: :json

    assert_response :success
    assert_equal @shard.channel_uuid, response_json["channel_uuid"]
  end

  test "cancel only cancels the intended active travel" do
    user = create_cancel_user
    first_ship, first_travel = create_active_cancel_travel(
      user: user,
      ship_guid: "cancel-ship-guid-1",
      travel_guid: "cancel-travel-guid-1"
    )
    _second_ship, second_travel = create_active_cancel_travel(
      user: user,
      ship_guid: "cancel-ship-guid-2",
      travel_guid: "cancel-travel-guid-2"
    )

    delete "/api/cancel",
      params: cancel_payload(player_guid: user.uid, ship_guid: first_ship.guid),
      headers: { "X-Secret-Guid" => "test-secret" },
      as: :json

    assert_response :success
    assert_equal first_travel.travel_guid, response_json["travel_guid"]
    assert_nil ShipTravel.find_by(id: first_travel.id)
    assert_equal second_travel, ShipTravel.find_by(id: second_travel.id)
  end

  test "cancel errors instead of cancelling arbitrarily when multiple active travels match" do
    user = create_cancel_user
    create_active_cancel_travel(user: user, ship_guid: "cancel-ship-guid-1", travel_guid: "cancel-travel-guid-1")
    create_active_cancel_travel(user: user, ship_guid: "cancel-ship-guid-2", travel_guid: "cancel-travel-guid-2")

    delete "/api/cancel",
      params: cancel_payload(player_guid: user.uid),
      headers: { "X-Secret-Guid" => "test-secret" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "error" => "Multiple active travels match this request. Provide ship_guid or travel_guid." },
      response_json
    )
    assert_equal 2, ShipTravel.count
  end

  private

  def travel_payload(overrides = {})
    {
      travel_guid: "client-travel-guid",
      ship_guid: "ship-guid",
      ship_slug: @ship.slug,
      player_guid: "player-guid",
      player_name: "TestPilot",
      to_location: @to_location.name,
      from_location: @from_location.name,
      shard_uuid: @shard.channel_uuid
    }.merge(overrides)
  end

  def create_shubin_22_location
    Location.create!(
      name: "Shubin Mining Facility SM0-22",
      classification: "outpost",
      star_system_name: "Stanton",
      planet_name: "MicroTech"
    )
  end

  def create_gateway_locations
    stanton_gateway_pyro = Location.create!(
      name: "Stanton Gateway (Pyro)",
      nickname: "Stanton Gateway (Pyro)",
      space_station_name: "Stanton Gateway (Pyro)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )
    nyx_gateway_pyro = Location.create!(
      name: "Nyx Gateway (Pyro)",
      nickname: "Nyx Gateway (Pyro)",
      space_station_name: "Nyx Gateway (Pyro)",
      orbit_name: "Nyx Gateway (Pyro system)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )
    nyx_gateway_stanton = Location.create!(
      name: "Nyx Gateway (Stanton)",
      nickname: "Nyx Gateway (Stanton)",
      space_station_name: "Nyx Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
    )

    [stanton_gateway_pyro, nyx_gateway_pyro, nyx_gateway_stanton]
  end

  def create_gateway(name, star_system_name)
    Location.create!(
      name: name,
      nickname: name,
      space_station_name: name,
      orbit_name: "#{name.sub(/\s*\([^)]*\)\s*\z/, "")} (#{star_system_name} system)",
      classification: "space_station",
      star_system_name: star_system_name,
      is_available: true,
      is_visible: true
    )
  end

  def create_existing_synced_ship_at(location, guid:)
    user = User.create!(
      username: "#{guid}-pilot",
      twitch_id: "#{guid}-player",
      uid: "#{guid}-player",
      user_type: "player"
    )
    shard_user = ShardUser.create!(user: user, shard: @shard, shard_name: @shard.name)

    UserShip.create!(
      user: user,
      ship: @ship,
      shard: @shard,
      shard_user: shard_user,
      shard_name: @shard.name,
      guid: guid,
      ship_slug: @ship.slug,
      location: location,
      total_scu: @ship.scu,
      used_scu: 0
    )
  end

  def create_cancel_user(uid: "cancel-player-guid", username: "CancelPilot")
    User.create!(
      username: username,
      twitch_id: "#{uid}-twitch",
      uid: uid,
      user_type: "player"
    )
  end

  def create_active_cancel_travel(user:, shard: @shard, ship_guid: "cancel-ship-guid", travel_guid: "cancel-travel-guid")
    shard_user = ShardUser.find_or_create_by!(user_id: user.id, shard_id: shard.id) do |su|
      su.shard_name = shard.name
      su.wallet_balance = 10_000
    end

    user_ship = UserShip.create!(
      user: user,
      ship: @ship,
      shard: shard,
      shard_user: shard_user,
      shard_name: shard.name,
      guid: ship_guid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "in_transit"
    )

    travel = ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: travel_guid,
      departure_tick: 10,
      arrival_tick: 20,
      total_duration_ticks: 10,
      interdict_window_percent: 50
    )

    [user_ship, travel]
  end

  def cancel_payload(overrides = {})
    {
      player_guid: "cancel-player-guid",
      shard_uuid: @shard.channel_uuid
    }.merge(overrides)
  end

  def response_json
    JSON.parse(response.body)
  end
end
