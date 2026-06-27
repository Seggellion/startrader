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

  def response_json
    JSON.parse(response.body)
  end
end
