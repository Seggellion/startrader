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
    assert_kind_of Hash, response_json["message"]
    assert_equal @location.name, response_json.dig("message", "location")
    assert_kind_of Array, response_json.dig("message", "commodities")
    refute_empty response_json.dig("message", "commodities")
    refute_includes response_json, "location"
    refute_includes response_json, "commodities"
  end

  test "buy with valid commodity name and scu still performs purchase with standard response keys" do
    post "/api/buy", params: {
      trade: base_trade_payload
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["status"]
    assert_kind_of String, response_json["message"]
    assert_includes response_json["message"], "Purchased 2 SCU of Terminal Buys This"
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
    assert_kind_of Hash, response_json["message"]
    assert_equal @location.name, response_json.dig("message", "location")
    commodities = response_json.dig("message", "commodities")
    assert_kind_of Array, commodities
    assert_equal 1, commodities.size
    assert_equal @sell_commodity.name, commodities.first["commodity_name"]
    assert_equal 384.56, commodities.first["sell_price"].to_f
    assert_equal 0, commodities.first["scu"]
    refute_includes response_json, "location"
    refute_includes response_json, "commodities"
  end

  test "buy and sell listings use different terminal market directions for the same location" do
    post "/api/buy", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    buy_names = response_json.dig("message", "commodities").map { |commodity| commodity["commodity_name"] }

    post "/api/sell", params: {
      trade: base_trade_payload.except(:commodity_name, :scu)
    }, as: :json

    assert_response :success
    sell_names = response_json.dig("message", "commodities").map { |commodity| commodity["commodity_name"] }

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
        { status: "success", message: { location: @location.name, commodities: [] } }
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

  def response_json
    JSON.parse(response.body)
  end
end
