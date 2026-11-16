require "test_helper"
require "minitest/mock"

# M01 — /admin/users/:id rebuild (discovery F-09, F-21; acceptance criteria 11-21).
class Admin::UserOverviewTest < ActionDispatch::IntegrationTest
  setup do
    [TravelArrivalEvent, TravelRequestReceipt, TravelResumeAction, StarBitizenRun, UserShipCargo,
     ShipTravel, UserShip, ShardUser, User, Ship, Shard, Location, Commodity, Setting, Tick].each(&:delete_all)
    Setting.create!(key: "seconds_per_tick", value: "15", setting_type: "text")
    Setting.create!(key: "secret_guid", value: "overview-secret-never-shown", setting_type: "text")
    MarketPriceUpdater.stub(:update_prices!, nil) { Tick.create!(current_tick: 100, sequence: 100) }

    @admin = User.create!(username: "OverviewAdmin", uid: "admin-uid", twitch_id: "admin-twitch",
      provider: "twitch", user_type: "admin")
    @player = User.create!(username: "Overview Pilot", uid: "pilot-uid-123", twitch_id: "pilot-twitch-123",
      provider: "twitch", user_type: "player", wallet_balance: 5)
    @hull = Ship.create!(model: "Overview Hull", slug: "overview-hull", scu: 10)
    @locations = %w[Alpha Beta Gamma Delta].to_h do |n|
      [n, Location.create!(name: "Overview #{n}", classification: "space_station", star_system_name: "Stanton")]
    end
    @old_omniauth = OmniAuth.config.test_mode
  end

  teardown do
    OmniAuth.config.test_mode = @old_omniauth
    OmniAuth.config.mock_auth[:twitch] = nil
  end

  test "renders every membership and ship with real per-shard wallets and comparison states" do
    world = build_world(@player, shards: 3, ships_per_shard: [3, 3, 2])
    sign_in(@admin)
    before = snapshot

    get "/admin/users/#{@player.id}"

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "[data-membership-id]", 3
    assert_select "article[data-ship-id]", 8
    world[:memberships].each do |su|
      assert_select "[data-membership-id='#{su.id}']", text: /#{Regexp.escape(su.shard.channel_uuid)}/
      assert_includes response.body, "#{ActiveSupport::NumberHelper.number_to_delimited(su.wallet_balance)} aUEC"
    end
    assert_includes response.body, "Platform wallet (legacy field, not gameplay credits)"
    assert_select "[data-comparison='aligned']", minimum: 1
    assert_select "[data-comparison='diverged']", 1
    assert_select "[data-comparison='in_transit']", 1
    assert_select "[data-comparison='interdicted']", 1
    assert_select "[data-summary='location-mismatches'] p", text: "1"
    assert_select "[data-summary='interdicted'] p", text: "1"
    assert_select "[data-summary='in-transit'] p", text: "1"
    assert_includes response.body, "Interdicted"
    assert_includes response.body, "(interdicted sentinel, not an arrival deadline)"
    assert_includes response.body, "No scheduled arrival while interdicted"
    assert_includes response.body, "Scheduled travel"
    assert_includes response.body, "No journey on record"
    assert_includes response.body, "UTC"
    assert_select "[data-location-instrumentation]", 3
    assert_includes response.body, "by an unrecorded source"
    assert_equal before, snapshot, "the admin page must not write"
  end

  test "historical last_location shapes render safely and coordinates appear only when present" do
    memberships = (1..5).map do |i|
      shard = Shard.create!(name: "Shape #{i}", region: "us", channel_uuid: "shape-#{i}")
      ShardUser.create!(user: @player, shard: shard, wallet_balance: 100 * i)
    end
    raw = ["'{}'::jsonb", "'\"Overview Alpha\"'::jsonb", "'[1,2,3]'::jsonb", "NULL",
           %q('{"name":"Overview Beta","x":1.5,"y":-2,"z":3}'::jsonb)]
    memberships.zip(raw).each { |su, sql| ShardUser.where(id: su.id).update_all("last_location = #{sql}") }
    sign_in(@admin)

    get "/admin/users/#{@player.id}"

    assert_response :success
    assert_select "[data-membership-id]", 5
    assert_select "[data-legacy-coordinates]", 1
    assert_select "[data-membership-id='#{memberships.last.id}'] [data-legacy-coordinates]", text: /x=1.5/
    assert_select "[data-membership-id='#{memberships.last.id}']", text: /Resolves \(Location ##{@locations['Beta'].id}\)/
    assert_operator response.body.scan("Unknown — no location recorded").size, :>=, 4
    assert_includes response.body, "Not recorded (before instrumentation"
  end

  test "stale catalog names, unlinked ships and missing memberships are labelled" do
    shard = Shard.create!(name: "Stale", region: "us", channel_uuid: "stale-shard")
    su = ShardUser.create!(user: @player, shard: shard, wallet_balance: 0)
    su.update_columns(last_location: { "name" => "Retired Station" })
    UserShip.create!(user: @player, ship: @hull, shard: shard, shard_user: su, guid: "stale-ship",
      location_name: "Gone Outpost", total_scu: 10, used_scu: 0)
    orphan = UserShip.create!(user: @player, ship: @hull, guid: "orphan-ship",
      location_name: @locations["Alpha"].name, total_scu: 10, used_scu: 0)
    sign_in(@admin)

    get "/admin/users/#{@player.id}"

    assert_response :success
    assert_select "[data-stale-location]", 2
    assert_select "[data-unlinked-ships] article[data-ship-id='#{orphan.id}']", 1
    assert_includes response.body, "not linked to any shard membership"

    lonely = User.create!(username: "Lonely", uid: "lonely", twitch_id: "lonely", user_type: "player")
    get "/admin/users/#{lonely.id}"
    assert_response :success
    assert_includes response.body, "No shard memberships"
  end

  test "query count does not grow with memberships, ships or journeys" do
    small = User.create!(username: "Small", uid: "small", twitch_id: "small", user_type: "player")
    build_world(small, shards: 2, ships_per_shard: [3, 2], prefix: "s")
    build_world(@player, shards: 3, ships_per_shard: [3, 3, 2], prefix: "b")
    sign_in(@admin)

    small_count = count_queries { get "/admin/users/#{small.id}" }
    assert_response :success
    big_count = count_queries { get "/admin/users/#{@player.id}" }
    assert_response :success

    assert_equal small_count, big_count, "3 shards x 8 ships must cost the same queries as 2 shards x 5 ships"
    assert_operator big_count, :<=, 30
  end

  test "anonymous visitors and players cannot see the overview" do
    build_world(@player, shards: 1, ships_per_shard: [1])

    get "/admin/users/#{@player.id}"
    assert_redirected_to login_path

    sign_in(@player, expect: root_path)
    get "/admin/users/#{@player.id}"
    assert_redirected_to root_path
  end

  test "no secret and no third-party avatar request carrying the uid" do
    build_world(@player, shards: 1, ships_per_shard: [1])
    sign_in(@admin)

    get "/admin/users/#{@player.id}"
    assert_response :success
    refute_includes response.body, "overview-secret-never-shown"
    refute_includes response.body, "crafatar"
    Nokogiri::HTML(response.body).css("img[src]").each do |img|
      refute_includes img["src"], @player.uid
    end

    get "/admin/users"
    assert_response :success
    refute_includes response.body, "crafatar"
  end

  private

  def sign_in(user, expect: admin_root_path)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:twitch] = OmniAuth::AuthHash.new(provider: "twitch", uid: user.uid, info: { name: user.username })
    get "/auth/twitch/callback"
    assert_redirected_to expect
  end

  # Builds memberships whose first ship is aligned. On the first shard: ship 2 is
  # diverged, ship 3 is in transit; on the second shard ship 2 is interdicted.
  def build_world(user, shards:, ships_per_shard:, prefix: "w")
    memberships = []
    shards.times do |i|
      shard = Shard.create!(name: "#{prefix} Shard #{i}", region: "us", channel_uuid: "#{prefix}-shard-#{i}")
      su = ShardUser.create!(user: user, shard: shard, wallet_balance: 1_000 * (i + 1) + 234)
      su.update_current_location!(@locations["Alpha"])
      memberships << su
      ships_per_shard[i].times do |j|
        ship = UserShip.create!(user: user, ship: @hull, shard: shard, shard_user: su, shard_name: shard.name,
          guid: "#{prefix}-#{i}-#{j}", location_name: @locations["Alpha"].name, total_scu: 10, used_scu: 2, status: "docked")
        commodity = Commodity.find_or_create_by!(name: "Overview cargo")
        UserShipCargo.create!(user_ship: ship, commodity: commodity, commodity_name: commodity.name, scu: 2, buy_price: 1.5)
        case [i, j]
        when [0, 1] then ship.update!(location_name: @locations["Gamma"].name)
        when [0, 2]
          ShipTravel.create!(user_ship: ship, from_location: @locations["Alpha"], to_location: @locations["Delta"],
            travel_guid: "#{prefix}-active", departure_tick: 95, arrival_tick: 110, total_duration_ticks: 15, rabbitmq_environment: "dev")
          ship.update!(status: "in_transit")
        when [1, 1]
          travel = ShipTravel.create!(user_ship: ship, from_location: @locations["Alpha"], to_location: @locations["Beta"],
            travel_guid: "#{prefix}-paused", departure_tick: 90, arrival_tick: 120, total_duration_ticks: 30, rabbitmq_environment: "prod")
          travel.interdict!(100)
          ship.update!(status: "interdicted")
        end
      end
    end
    { memberships: memberships }
  end

  def snapshot
    [User, ShardUser, UserShip, ShipTravel, UserShipCargo, Shard].map do |model|
      model.order(:id).pluck(:id, :updated_at)
    end
  end

  def count_queries
    count = 0
    callback = lambda do |*, payload|
      # Cached calls count too: the test connection keeps its query cache between
      # requests, and an N+1 is a growing number of calls whether cached or not.
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql] =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i
      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
