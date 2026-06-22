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
      name: "Area18",
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
    @commodity = Commodity.create!(name: "Agricium", is_sellable: true)
    @facility = ProductionFacility.create!(
      facility_name: @location.name,
      location_name: @location.name,
      commodity_name: @commodity.name,
      production_rate: 1,
      consumption_rate: 1,
      inventory: 10,
      max_inventory: 20,
      local_buy_price: 123
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
    assert_includes response_json["message"], "Purchased 2 SCU of Agricium"
    assert_equal 2, @user_ship.reload.used_scu
    assert_equal 8, @facility.reload.inventory
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

  def response_json
    JSON.parse(response.body)
  end
end
