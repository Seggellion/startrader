require "test_helper"

class Api::TradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    ProductionFacility.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all
    Setting.create!(key: "seconds_per_tick", value: "5", setting_type: "text")
    Setting.create!(key: "secret_guid", value: "test-secret", setting_type: "text")

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-guid")
    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @shard_user = ShardUser.create!(
      user: @user,
      shard_id: @shard.id,
      shard_name: @shard.name,
      wallet_balance: 10_000
    )
    @location = Location.create!(
      name: "Test Location",
      classification: "city",
      star_system_name: "Stanton"
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "ship-guid",
      ship_slug: @ship.slug,
      location_name: @location.name,
      total_scu: @ship.scu,
      used_scu: 0
    )
    @commodity = Commodity.create!(name: "Terminal Buys This", is_sellable: true)
    @sell_commodity = Commodity.create!(name: "Terminal Sells This", is_sellable: false)
    @facility = ProductionFacility.create!(
      facility_name: "Test Producer",
      location_name: @location.name,
      commodity_name: @commodity.name,
      production_rate: 5,
      consumption_rate: 0,
      inventory: 1000,
      max_inventory: 2000,
      local_buy_price: 9.62,
      local_sell_price: nil,
      price_buy: 12.0,
      price_sell: 0.0,
      scu_buy: 10,
      status_buy: 7,
      status_sell: 0
    )
    @sell_facility = ProductionFacility.create!(
      facility_name: "Test TDD",
      location_name: @location.name,
      commodity_name: @sell_commodity.name,
      terminal_name: "Test TDD",
      production_rate: 0,
      consumption_rate: 5,
      inventory: 0,
      max_inventory: 20,
      local_buy_price: nil,
      local_sell_price: 384.56,
      price_buy: 0.0,
      price_sell: 326.0,
      scu_buy: 0,
      scu_sell_stock: 0,
      status_buy: 0,
      status_sell: 1
    )
  end

  test "buy without commodity name and scu lists commodities in standard response shape" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_kind_of String, response_json["message"]
    assert_equal @location.name, response_json["location"]
    assert_kind_of Array, response_json["commodities"]
    refute_empty response_json["commodities"]
    refute response_json.key?("total_capital")
    response_json["commodities"].each { |commodity| refute commodity.key?("total_capital") }
    refute_includes response_json["message"], "location"
    refute_includes response_json["message"], "commodities"
  end

  test "buy with valid commodity name and scu still performs purchase with standard response keys" do
    post "/api/buy", params: {
      trade: base_trade_payload
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_kind_of String, response_json["message"]
    assert_includes response_json["message"], "Purchased 2 SCU of Terminal Buys This"
    assert_equal 70, response_json["loading_time"]
    assert_equal 14, response_json["loading_ticks"]
    assert_equal 19.24, response_json["capital"]
    assert_equal 19.24, response_json["total_capital"]
    assert_equal 2, @user_ship.reload.used_scu
    assert_equal 998, @facility.reload.inventory
    assert_equal 1, UserShipCargo.where(user_ship: @user_ship, commodity: @commodity, scu: 2).count
  end

  test "buy missing only commodity name returns validation error" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:commodity_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing commodity name for purchase." },
      response_json
    )
  end

  test "buy with blank scu lists commodities even when commodity name contains parsed amount" do
    post "/api/buy", params: {
      trade: base_trade_payload.merge(commodity_name: "5", scu: "")
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_equal @location.name, response_json["location"]
    assert_kind_of Array, response_json["commodities"]
    assert_includes response_json["commodities"].map { |commodity| commodity["commodity_name"] }, @commodity.name
    refute response_json.key?("total_capital")
  end

  test "buy missing only scu returns validation error" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:scu)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing SCU amount for purchase." },
      response_json
    )
  end

  test "buy missing player name returns missing required parameters" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:player_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing required parameters" },
      response_json
    )
  end

  test "buy missing shard name returns missing required parameters" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:shard_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing required parameters" },
      response_json
    )
  end

  test "sell without commodity name and scu lists terminal sell-side commodities in standard response shape" do
    post "/api/sell", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_kind_of String, response_json["message"]
    assert_equal @location.name, response_json["location"]
    commodities = response_json["commodities"]
    assert_kind_of Array, commodities
    assert_equal 1, commodities.size
    assert_equal @sell_commodity.name, commodities.first["commodity_name"]
    assert_equal 384.56, commodities.first["sell_price"].to_f
    assert_equal 0, commodities.first["scu"]
    refute response_json.key?("total_capital")
    commodities.each { |commodity| refute commodity.key?("total_capital") }
    refute_includes response_json["message"], "location"
    refute_includes response_json["message"], "commodities"
  end

  test "buy and sell listings use different terminal market directions for the same location" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    buy_names = response_json["commodities"].map { |commodity| commodity["commodity_name"] }

    post "/api/sell", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    sell_names = response_json["commodities"].map { |commodity| commodity["commodity_name"] }

    assert_includes buy_names, "Terminal Buys This"
    refute_includes buy_names, "Terminal Sells This"
    assert_includes sell_names, "Terminal Sells This"
    refute_includes sell_names, "Terminal Buys This"
    assert_empty buy_names & sell_names
  end

  test "blank sell delegates to sellable commodity listing" do
    called = false

    TradeService.stub(:list_available_commodities, ->(**) { raise "blank sell must not use buy listing" }) do
      TradeService.stub(:list_sellable_commodities, ->(username:, shard:) {
        called = true
        assert_equal @user.username, username
        assert_equal @shard.name, shard
        {
          status: "success",
          message: "Commodities available to sell at #{@location.name}.",
          location: @location.name,
          commodities: []
        }
      }) do
        post "/api/sell", params: {
          trade: base_trade_payload.except(:commodity_name, :scu)
        }, as: :json
      end
    end

    assert_response :success
    assert called
  end

  test "sell missing only commodity name returns validation error" do
    post "/api/sell", params: {
      trade: base_trade_payload.except(:commodity_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing commodity name for sale." },
      response_json
    )
  end

  test "sell missing only scu returns validation error" do
    post "/api/sell", params: {
      trade: base_trade_payload.except(:scu)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing SCU amount for sale." },
      response_json
    )
  end

  test "sell with valid commodity name and scu still performs sale with standard response keys" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @sell_commodity, scu: 3)

    post "/api/sell", params: {
      trade: sell_trade_payload
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_kind_of String, response_json["message"]
    assert_includes response_json["message"], "Sold 2 SCU of Terminal Sells This"
    assert_equal 769.12, response_json["profit"]
    assert_equal 769.12, response_json["total_capital"]
    assert_equal 1, cargo.reload.scu
    assert_equal 2, @sell_facility.reload.inventory
    assert_in_delta 10_769.12, @shard_user.reload.wallet_balance.to_f, 0.01
  end

  test "sell missing player name returns missing required parameters" do
    post "/api/sell", params: {
      trade: base_trade_payload.except(:player_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing required parameters" },
      response_json
    )
  end

  test "sell missing shard name returns missing required parameters" do
    post "/api/sell", params: {
      trade: base_trade_payload.except(:shard_name)
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal(
      { "status" => "error", "message" => "Missing required parameters" },
      response_json
    )
  end

  test "status accepts new authenticated payload and keeps response shape" do
    post "/api/status", params: base_status_payload, as: :json

    assert_response :success
    assert_equal ["cargo", "player_location", "ship", "ships", "status", "wallet_balance"], response_json.keys.sort
    assert_equal "success", response_json["status"]
    assert_equal 40_000, response_json["wallet_balance"]
    assert_equal(
      [
        "arrival_tick",
        "available_cargo_space",
        "available_at_player_location",
        "current_tick",
        "from_location",
        "location",
        "model",
        "time_remaining",
        "to_location",
        "total_scu",
        "travel_status",
        "unavailable_reason",
        "used_scu"
      ],
      response_json["ship"].keys.sort
    )
    assert_equal @ship.model, response_json["ship"]["model"]
    assert_equal @location.name, response_json["ship"]["location"]
    assert_equal @location.name, response_json["player_location"]
    assert_equal true, response_json["ship"]["available_at_player_location"]
    assert_nil response_json["ship"]["unavailable_reason"]
    assert_equal [@user_ship.guid], response_json["ships"].map { |ship| ship["guid"] }
  end

  test "status updates username from player name for existing twitch id" do
    post "/api/status", params: base_status_payload.merge(player_name: "RenamedPilot"), as: :json

    assert_response :success
    assert_equal "RenamedPilot", @user.reload.username
  end

  test "status accepts new authenticated payload nested under trade" do
    post "/api/status", params: { trade: base_status_payload }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_equal 40_000, response_json["wallet_balance"]
    assert_equal @ship.model, response_json["ship"]["model"]
    assert_equal @location.name, response_json["ship"]["location"]
  end

  test "status with top-level location updates shard user and matching ship" do
    new_location = Location.create!(
      name: "Area 18",
      classification: "city",
      star_system_name: "Stanton"
    )

    post "/api/status", params: base_status_payload.merge(location: new_location.name), as: :json

    assert_response :success
    assert_equal new_location.name, @shard_user.reload.current_location_name
    assert_equal new_location.name, @user_ship.reload.location_name
    assert_equal new_location.name, response_json["player_location"]
    assert_equal new_location.name, response_json["ship"]["location"]
  end

  test "status with nested trade location updates shard user and matching ship" do
    new_location = Location.create!(
      name: "Area 18",
      classification: "city",
      star_system_name: "Stanton"
    )

    post "/api/status", params: { trade: base_status_payload.merge(location: new_location.name) }, as: :json

    assert_response :success
    assert_equal new_location.name, @shard_user.reload.current_location_name
    assert_equal new_location.name, @user_ship.reload.location_name
  end

  test "status without location preserves existing location fields" do
    @shard_user.update_current_location!(@location)

    post "/api/status", params: base_status_payload, as: :json

    assert_response :success
    assert_equal @location.name, @shard_user.reload.current_location_name
    assert_equal @location.name, @user_ship.reload.location_name
  end

  test "status with unknown location returns error and preserves existing locations" do
    @shard_user.update_current_location!(@location)

    post "/api/status", params: base_status_payload.merge(location: "Not A Real Place"), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "Location not found: Not A Real Place" }, response_json)
    assert_equal @location.name, @shard_user.reload.current_location_name
    assert_equal @location.name, @user_ship.reload.location_name
  end

  test "status location updates only ship matching ship_guid" do
    new_location = Location.create!(
      name: "Area 18",
      classification: "city",
      star_system_name: "Stanton"
    )
    other_ship = Ship.create!(model: "MISC Hull A", slug: "misc-hull-a", scu: 64, speed: 80)
    other_user_ship = UserShip.create!(
      user: @user,
      ship: other_ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "other-ship-guid",
      ship_slug: other_ship.slug,
      location_name: @location.name,
      total_scu: other_ship.scu,
      used_scu: 0
    )

    post "/api/status", params: base_status_payload.merge(location: new_location.name), as: :json

    assert_response :success
    assert_equal new_location.name, @user_ship.reload.location_name
    assert_equal @location.name, other_user_ship.reload.location_name
  end

  test "status uses username only as player name fallback for new payload" do
    post "/api/status",
      params: base_status_payload.except(:player_name).merge(username: @user.username),
      as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
  end

  test "status still accepts legacy username and shard payload" do
    post "/api/status",
      params: {
        username: @user.username,
        shard: @shard.channel_uuid,
        secret_guid: "test-secret"
      },
      as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_equal @ship.model, response_json["ship"]["model"]
  end

  test "status with legacy location updates shard user and current ship" do
    new_location = Location.create!(
      name: "Area 18",
      classification: "city",
      star_system_name: "Stanton"
    )

    post "/api/status",
      params: {
        username: @user.username,
        shard: @shard.channel_uuid,
        location: new_location.name,
        secret_guid: "test-secret"
      },
      as: :json

    assert_response :success
    assert_equal new_location.name, @shard_user.reload.current_location_name
    assert_equal new_location.name, @user_ship.reload.location_name
  end

  test "status rejects missing secret_guid" do
    post "/api/status", params: base_status_payload.except(:secret_guid), as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "status rejects invalid secret_guid" do
    post "/api/status", params: base_status_payload.merge(secret_guid: "wrong"), as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response_json)
  end

  test "status requires ship_guid" do
    post "/api/status", params: base_status_payload.except(:ship_guid), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "ship_guid is required" }, response_json)
  end

  test "status requires ship_model" do
    post "/api/status", params: base_status_payload.except(:ship_model), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "ship_model is required" }, response_json)
  end

  test "status requires shard_uuid" do
    post "/api/status", params: base_status_payload.except(:shard_uuid), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "shard_uuid is required" }, response_json)
  end

  test "status requires player_guid" do
    post "/api/status", params: base_status_payload.except(:player_guid), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "player_guid is required" }, response_json)
  end

  test "status requires player_name" do
    post "/api/status", params: base_status_payload.except(:player_name), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "player_name is required" }, response_json)
  end

  test "status rejects unknown shard_uuid" do
    post "/api/status", params: base_status_payload.merge(shard_uuid: "unknown"), as: :json

    assert_response :not_found
    assert_equal({ "status" => "error", "message" => "Shard not found" }, response_json)
  end

  test "status creates unknown ship with valid ship model" do
    new_guid = "new-status-ship-guid"

    assert_difference("UserShip.count", 1) do
      post "/api/status", params: base_status_payload.merge(ship_guid: new_guid), as: :json
    end

    assert_response :success
    created_ship = UserShip.find_by!(guid: new_guid)
    assert_equal @ship, created_ship.ship
    assert_equal @user, created_ship.user
    assert_equal @shard, created_ship.shard
    assert_equal @shard_user, created_ship.shard_user
    assert_equal "success", response_json["status"]
    assert_equal @ship.model, response_json["ship"]["model"]
  end

  test "status creates unknown user and shard user from player guid" do
    new_guid = "new-player-status-ship-guid"

    assert_difference("User.count", 1) do
      assert_difference("ShardUser.count", 1) do
        post "/api/status",
          params: base_status_payload.merge(
            ship_guid: new_guid,
            player_guid: "new-player-guid",
            player_name: "NewPilot"
          ),
          as: :json
      end
    end

    assert_response :success
    created_user = User.find_by!(twitch_id: "new-player-guid")
    created_shard_user = ShardUser.find_by!(user: created_user, shard_id: @shard.id)
    created_ship = UserShip.find_by!(guid: new_guid)
    assert_equal "NewPilot", created_user.username
    assert_equal "new-player-guid", created_user.uid
    assert_equal @shard.name, created_shard_user.shard_name
    assert_equal created_user, created_ship.user
    assert_equal created_shard_user, created_ship.shard_user
  end

  test "status creates unknown ship with case insensitive trimmed ship model" do
    new_guid = "case-insensitive-status-ship-guid"

    assert_difference("UserShip.count", 1) do
      post "/api/status", params: base_status_payload.merge(ship_guid: new_guid, ship_model: " #{@ship.model.downcase} "), as: :json
    end

    assert_response :success
    assert_equal @ship, UserShip.find_by!(guid: new_guid).ship
    assert_equal @ship.model, response_json["ship"]["model"]
  end

  test "status rejects unknown ship model when creating ship" do
    post "/api/status", params: base_status_payload.merge(ship_guid: "new-status-ship-guid", ship_model: "Unknown Model"), as: :json

    assert_response :not_found
    assert_equal({ "status" => "error", "message" => "Ship model not found" }, response_json)
  end

  test "status requires player name before creating unknown ship" do
    post "/api/status", params: base_status_payload.except(:player_name).merge(ship_guid: "new-status-ship-guid"), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "player_name is required" }, response_json)
  end

  test "status rejects existing ship for different player" do
    other_user = User.create!(
      username: "OtherPilot",
      twitch_id: "other-player-guid",
      uid: "other-player-guid",
      user_type: "player"
    )
    ShardUser.create!(
      user: other_user,
      shard_id: @shard.id,
      shard_name: @shard.name,
      wallet_balance: 0
    )

    post "/api/status",
      params: base_status_payload.merge(player_guid: other_user.twitch_id, player_name: other_user.username),
      as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "Ship does not belong to this player" }, response_json)
  end

  test "status rejects existing ship for different shard" do
    other_shard = Shard.create!(name: "OtherShard", region: "us", channel_uuid: "other-shard-guid")

    post "/api/status",
      params: base_status_payload.merge(shard_uuid: other_shard.channel_uuid),
      as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "Ship does not belong to this shard" }, response_json)
  end

  test "repeated status calls with same ship guid do not create duplicate ships" do
    new_guid = "repeat-controller-status-ship-guid"

    assert_difference("UserShip.count", 1) do
      post "/api/status", params: base_status_payload.merge(ship_guid: new_guid), as: :json
      assert_response :success

      post "/api/status", params: base_status_payload.merge(ship_guid: new_guid), as: :json
      assert_response :success
    end
  end

  test "status updates wallet balance" do
    post "/api/status", params: base_status_payload.merge(wallet_balance: 60_000), as: :json

    assert_response :success
    assert_equal 60_000, @shard_user.reload.wallet_balance
    assert_equal 60_000, response_json["wallet_balance"]
  end

  test "status rejects non numeric wallet balance" do
    post "/api/status", params: base_status_payload.merge(wallet_balance: "not-money"), as: :json

    assert_response :bad_request
    assert_equal({ "status" => "error", "message" => "wallet_balance must be numeric" }, response_json)
  end

  private

  def base_trade_payload
    {
      player_name: @user.username,
      wallet_balance: 10_000,
      commodity_name: @commodity.name,
      scu: 2,
      shard_name: @shard.name,
      ship_guid: @user_ship.guid,
      ship_slug: @ship.slug
    }
  end

  def sell_trade_payload
    base_trade_payload.merge(commodity_name: @sell_commodity.name)
  end

  def base_status_payload
    {
      ship_guid: @user_ship.guid,
      ship_model: @ship.model,
      wallet_balance: 40_000,
      shard_uuid: @shard.channel_uuid,
      player_guid: @user.twitch_id,
      player_name: @user.username,
      secret_guid: "test-secret"
    }
  end

  def response_json
    JSON.parse(response.body)
  end
end
