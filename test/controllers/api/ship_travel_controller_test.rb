require "test_helper"

class Api::ShipTravelControllerTest < ActionDispatch::IntegrationTest
  setup do
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
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

  def response_json
    JSON.parse(response.body)
  end
end
