require "test_helper"
require_relative "../support/travel_repair_fixtures"

# M05 — absolute instants as integer Unix seconds; ticks untouched (discovery
# §6, F-13; decisions Q5, Q6).
class UnixTimeContractTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  include DisplayTimeHelper
  setup { setup_travel_repair }

  def status_payload
    { ship_guid: @hull.guid, ship_model: @catalog_ship.model, shard_uuid: @shard.channel_uuid,
      player_guid: @user.uid, player_name: @user.username, secret_guid: "repair-secret" }
  end

  test "arrival_at_unix is integer epoch seconds derived from remaining ticks" do
    travel = gate_start
    travel_to Time.utc(2026, 11, 16, 12, 0, 0) do
      value = travel.arrival_at_unix(100)
      assert_kind_of Integer, value
      assert_equal 10, value.to_s.length, "seconds, not milliseconds"
      assert_equal Time.current.to_i + (travel.arrival_tick - 100) * 15, value
    end
  end

  test "a stalled tick chain moves the estimate forward instead of claiming a past arrival" do
    travel = gate_start
    first = travel_to(Time.utc(2026, 11, 16, 12, 0, 0)) { travel.arrival_at_unix(100) }
    later = travel_to(Time.utc(2026, 11, 16, 12, 5, 0)) { travel.arrival_at_unix(100) }
    assert_equal 300, later - first
  end

  test "interdiction sentinel and completion never become a Unix instant" do
    travel = gate_start
    travel.interdict!(100)
    assert_equal 0, travel.reload.arrival_tick
    assert_nil travel.arrival_at_unix(100)
    assert_equal travel.remaining_ticks_from_arrival * 15, travel.remaining_travel_seconds(100)
    travel.update_columns(is_paused: false, arrival_tick: 120, completed_at_tick: 120)
    assert_nil travel.reload.arrival_at_unix(130)
  end

  test "status keeps legacy keys and adds paused-aware duration and instants (Q6)" do
    travel = gate_start
    travel.interdict!(100)
    @hull.update!(status: "interdicted")

    post "/api/status", params: status_payload, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal 0, body.dig("ship", "time_remaining"), "legacy key unchanged by decision Q6"
    assert_equal body.dig("travel", "time_remaining"), body.dig("ship", "remaining_travel_seconds")
    assert_operator body.dig("ship", "remaining_travel_seconds"), :>, 0
    assert_nil body.dig("ship", "arrival_at_unix")
    assert_nil body.dig("travel", "arrival_at_unix")
    assert_equal 0, body.dig("travel", "arrival_tick")
    assert_kind_of Integer, body["server_time_at_unix"]
    assert_in_delta Time.current.to_i, body["server_time_at_unix"], 5
  end

  test "active journeys expose arrival_at_unix on status, location and gate responses" do
    travel = gate_start
    post "/api/status", params: status_payload, as: :json
    status_value = response.parsed_body.dig("travel", "arrival_at_unix")
    assert_kind_of Integer, status_value

    get "/api/location/#{@hull.id}"
    assert_kind_of Integer, response.parsed_body["arrival_at_unix"]
    assert_in_delta status_value, response.parsed_body["arrival_at_unix"], 2
    assert_equal travel.arrival_tick, response.parsed_body["arrival_tick"]

    post "/api/gate_travel", params: { ship_guid: @hull.guid, travel_guid: travel.travel_guid,
      gateway_name: "Repair B Gateway", secret_guid: "repair-secret" }, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["request_replayed"]
    assert_kind_of Integer, response.parsed_body["arrival_at_unix"]
    assert_kind_of Integer, response.parsed_body["server_time_at_unix"]
  end

  test "the positional ShipArrival message is unchanged" do
    travel = gate_start
    fields = RabbitmqSender.ship_report_payload(travel)[:fields] || RabbitmqSender.ship_report_payload(travel)["fields"]
    assert_equal 13, fields.size
    assert_equal "ShipArrival", fields[1]
    assert_equal [travel.departure_tick, travel.arrival_tick], fields[3, 2]
    refute fields.any? { |f| f.is_a?(Integer) && f.to_s.length == 10 }, "no Unix instant added to the message"
  end

  test "display times always carry a zone and follow DST in a configured zone" do
    assert_equal "2026-07-01 12:00:00 UTC", display_time(Time.utc(2026, 7, 1, 12))
    assert_equal "Not recorded", display_time(nil)

    @display_time_zone = nil
    Setting.create!(key: "admin_display_time_zone", value: "Pacific Time (US & Canada)", setting_type: "text")
    assert_equal "2026-03-08 01:59:00 PST", display_time(Time.utc(2026, 3, 8, 9, 59))
    assert_equal "2026-03-08 03:00:00 PDT", display_time(Time.utc(2026, 3, 8, 10, 0))
    assert_equal "2026-11-01 01:30:00 PST", display_time(Time.utc(2026, 11, 1, 9, 30))
  end
end
