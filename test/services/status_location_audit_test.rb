require "test_helper"

# M01 — read-only location integrity audit (discovery P-02..P-05, N-01).
class StatusLocationAuditTest < ActiveSupport::TestCase
  setup do
    [TravelArrivalEvent, TravelRequestReceipt, TravelResumeAction, StarBitizenRun, UserShipCargo,
     ShipTravel, UserShip, ShardUser, User, Ship, Shard, Location].each(&:delete_all)
    @here = Location.create!(name: "Audit Here", classification: "city", star_system_name: "Stanton")
    @there = Location.create!(name: "Audit There", classification: "city", star_system_name: "Stanton")
    @hull = Ship.create!(model: "Audit Hull", slug: "audit-hull", scu: 4)
    @shard = Shard.create!(name: "Audit Shard", region: "us", channel_uuid: "Audit-UUID")
    Shard.create!(name: "Audit Shard twin", region: "us", channel_uuid: " audit-uuid ")
    @user = User.create!(username: "Secret Pilot Name", uid: "secret-uid", twitch_id: "secret-twitch", user_type: "player")

    @aligned = player_with_ship("aligned-guid", player_at: @here, ship_at: @here)
    @diverged = player_with_ship("diverged-guid", player_at: @here, ship_at: @there)
    @unknown = player_with_ship("unknown-guid", player_at: nil, ship_at: @here)
    @stale = player_with_ship("stale-guid", player_at: nil, ship_at: nil)
    @stale.update_columns(last_location: { "name" => "Retired Place", "x" => 1, "y" => 2, "z" => 3 })
    paused = player_with_ship("paused-guid", player_at: @here, ship_at: @here)
    travel = ShipTravel.create!(user_ship: paused.user_ships.first, from_location: @here, to_location: @there,
      travel_guid: "audit-paused", departure_tick: 1, arrival_tick: 9, total_duration_ticks: 8, rabbitmq_environment: "dev")
    travel.interdict!(3)
    TravelRequestReceipt.create!(travel_guid: "audit-done", user_ship_id: @aligned.user_ships.first.id,
      request_context: {}, travel_snapshot: {}, outcome: "completed", completed_at_tick: 2)
    TravelRequestReceipt.create!(travel_guid: "audit-paused-receipt", user_ship_id: paused.user_ships.first.id,
      request_context: {}, travel_snapshot: {}, outcome: "pending")
  end

  test "reports aggregate integrity counts" do
    report = StatusLocationAudit.new.report

    assert_equal 5, report[:shard_users][:total]
    assert_equal 1, report[:shard_users][:with_coordinate_keys]
    assert_equal 1, report[:shard_users][:location_not_in_catalog]
    assert_equal 1, report[:shards][:case_or_whitespace_variant_groups]
    assert_equal 2, report[:shards][:shards_in_variant_groups]
    assert_equal 1, report[:ships][:location_blank]
    assert_equal({ aligned: 1, diverged: 1, unknown: 2, in_transit: 0, interdicted: 1 }, report[:pairs])
    assert_equal 2, report[:receipts][:ships_with_receipts]
    assert_equal 1, report[:receipts][:ships_status_locked_while_idle]
    assert_equal 1, report[:journeys][:paused_zero_sentinel]
    assert_kind_of Integer, report[:generated_at_unix]
  end

  test "output carries no identifiers and the audit only reads" do
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    report = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { StatusLocationAudit.new.report }

    json = JSON.generate(report)
    ["Secret Pilot Name", "secret-uid", "secret-twitch", "aligned-guid", "Audit-UUID", "Audit Here", "Retired Place"].each do |value|
      refute_includes json, value
    end
    writes = statements.grep(/\A\s*(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|TRUNCATE)\b/i)
    assert_empty writes
  end

  private

  def player_with_ship(guid, player_at:, ship_at:)
    shard = Shard.find_or_create_by!(name: "Audit #{guid}", region: "us", channel_uuid: "audit-#{guid}")
    user = User.create!(username: "u-#{guid}", uid: "uid-#{guid}", twitch_id: "tw-#{guid}", user_type: "player")
    su = ShardUser.create!(user: user, shard: shard)
    su.update_current_location!(player_at) if player_at
    UserShip.create!(user: user, ship: @hull, shard: shard, shard_user: su, guid: guid,
      location_name: ship_at&.name, total_scu: 4, used_scu: 0)
    su
  end
end
