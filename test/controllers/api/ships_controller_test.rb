require "test_helper"

class Api::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Setting.delete_all
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all

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
    @ship = Ship.create!(model: "Drake Caterpillar", slug: "drake-caterpillar", scu: 100, speed: 100)
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "ship-guid",
      ship_slug: @ship.slug,
      total_scu: @ship.scu,
      used_scu: 0
    )
    @commodity = Commodity.create!(name: "Aluminum", is_sellable: true)
    @other_commodity = Commodity.create!(name: "Copper", is_sellable: true)
    @gold = Commodity.create!(name: "Gold", is_sellable: true)
  end

  test "ships index allows cors requests from maidenbot overlay origin" do
    @ship.update!(
      is_spaceship: true,
      is_ground_vehicle: false,
      name: "Drake Caterpillar",
      company_name: "Drake Interplanetary",
      length: 111
    )

    get "/api/ships", headers: { "Origin" => "https://maidenbot.com" }

    assert_response :success
    assert_equal "https://maidenbot.com", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Vary"], "Origin"
    assert_equal "Drake Caterpillar", response_json.first["shipname"]
  end

  test "ships index still allows existing starbitizen origin" do
    get "/api/ships", headers: { "Origin" => "https://starbitizen.com" }

    assert_response :success
    assert_equal "https://starbitizen.com", response.headers["Access-Control-Allow-Origin"]
  end

  test "ships index does not allow unlisted cors origins" do
    get "/api/ships", headers: { "Origin" => "https://example.com" }

    assert_response :success
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "ships index handles maidenbot cors preflight" do
    options "/api/ships", headers: {
      "Origin" => "https://maidenbot.com",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "Content-Type"
    }

    assert_response :success
    assert_equal "https://maidenbot.com", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Allow-Methods"], "GET"
    assert_includes response.headers["Access-Control-Allow-Headers"], "Content-Type"
  end

  test "dump cargo with one cargo type returns jettison message" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 24)
    run = StarBitizenRun.create!(
      user: @user,
      user_ship: @user_ship,
      user_ship_cargo: cargo,
      commodity: @commodity,
      commodity_name: @commodity.name,
      profit: 0,
      scu: 24
    )

    post "/api/ships/dump_cargo", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal(
      { "Status" => "success", "Message" => "jettisoned 24 scu of aluminum", "ErrorText" => "" },
      response_json
    )
    assert_dump_response_shape
    assert_equal 0, @user_ship.user_ship_cargos.count
    assert_equal 0, @user_ship.reload.used_scu
    assert_nil run.reload.user_ship_cargo_id
  end

  test "dump cargo with multiple cargo types returns readable combined message" do
    UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 10)
    UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 14)
    UserShipCargo.create!(user_ship: @user_ship, commodity: @other_commodity, scu: 12)
    UserShipCargo.create!(user_ship: @user_ship, commodity: @gold, scu: 6)

    post "/api/ships/dump_cargo", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["Status"]
    assert_equal "jettisoned 24 scu of aluminum, 12 scu of copper, and 6 scu of gold", response_json["Message"]
    assert_equal "", response_json["ErrorText"]
    assert_dump_response_shape
    assert_equal 0, @user_ship.user_ship_cargos.count
    assert_equal 0, @user_ship.reload.used_scu
  end

  test "dump cargo for ship with no cargo returns success message" do
    @user_ship.recalculate_used_scu!

    post "/api/ships/dump_cargo", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "test-secret"
    }, as: :json

    assert_response :success
    assert_equal "success", response_json["Status"]
    assert_equal "no cargo to jettison", response_json["Message"]
    assert_equal "", response_json["ErrorText"]
    assert_dump_response_shape
    assert_equal 0, @user_ship.reload.used_scu
  end

  test "dump cargo requires ship_guid" do
    post "/api/ships/dump_cargo", params: {
      secret_guid: "test-secret"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "Status" => "error", "Message" => "", "ErrorText" => "Missing ship_guid." }, response_json)
    assert_dump_response_shape
  end

  test "dump cargo requires secret_guid" do
    post "/api/ships/dump_cargo", params: {
      ship_guid: @user_ship.guid
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "Status" => "error", "Message" => "", "ErrorText" => "Missing secret_guid." }, response_json)
    assert_dump_response_shape
  end

  test "dump cargo rejects invalid secret using endpoint response shape" do
    post "/api/ships/dump_cargo", params: {
      ship_guid: @user_ship.guid,
      secret_guid: "wrong-secret"
    }, as: :json

    assert_response :unauthorized
    assert_equal({ "Status" => "error", "Message" => "", "ErrorText" => "Unauthorized" }, response_json)
    assert_dump_response_shape
  end

  test "dump cargo returns standard error for unknown ship_guid" do
    post "/api/ships/dump_cargo", params: {
      ship_guid: "missing-ship-guid",
      secret_guid: "test-secret"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal({ "Status" => "error", "Message" => "", "ErrorText" => "Ship not found." }, response_json)
    assert_dump_response_shape
  end

  private

  def assert_dump_response_shape
    assert_includes response_json, "Status"
    assert_includes response_json, "Message"
    assert_includes response_json, "ErrorText"
    refute_includes response_json, "status"
    refute_includes response_json, "message"
  end

  def response_json
    JSON.parse(response.body)
  end
end
