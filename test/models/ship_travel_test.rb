require "test_helper"

class ShipTravelTest < ActiveSupport::TestCase
  setup do
    ShipTravel.delete_all
    UserShip.delete_all
    User.delete_all
    Ship.delete_all
    Location.delete_all

    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
  end

  test "cleanup removes stale incomplete unpaused travel and recovers in transit ship status" do
    user_ship = create_user_ship(status: "in_transit")
    travel = create_travel(user_ship: user_ship, arrival_tick: 100)

    cleaned_count = ShipTravel.cleanup_stale_after_arrival!(105)

    assert_equal 1, cleaned_count
    refute ShipTravel.exists?(travel.id)
    assert_equal "aimlessly floating in space", user_ship.reload.status
  end

  test "cleanup removes current tick arrival" do
    travel = create_travel(arrival_tick: 105)

    assert_equal 1, ShipTravel.cleanup_stale_after_arrival!(105)
    refute ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove future travel" do
    travel = create_travel(arrival_tick: 106)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove paused interdicted travel with zero arrival tick" do
    travel = create_travel(arrival_tick: 0, is_paused: true)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove paused interdicted travel with past arrival tick" do
    travel = create_travel(arrival_tick: 100, is_paused: true)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup removes completed travel rows left by the old lifecycle" do
    travel = create_travel(arrival_tick: 100, completed_at_tick: 100)

    assert_equal 1, ShipTravel.cleanup_stale_after_arrival!(105)
    refute ShipTravel.exists?(travel.id)
  end

  test "cleanup is idempotent" do
    create_travel(arrival_tick: 100)

    assert_equal 1, ShipTravel.cleanup_stale_after_arrival!(105)
    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
  end

  test "cleanup destroys stale travel so destroy callbacks run" do
    destroyed_ids = []
    callback = -> { destroyed_ids << id }
    ShipTravel.set_callback(:destroy, :after, callback)
    travel = create_travel(arrival_tick: 100)

    ShipTravel.cleanup_stale_after_arrival!(105)

    assert_equal [travel.id], destroyed_ids
  ensure
    ShipTravel.skip_callback(:destroy, :after, callback) if callback
  end

  test "defaults to the production rabbitmq environment" do
    travel = create_travel(arrival_tick: 100)

    assert_equal "prod", travel.rabbitmq_environment
    assert_equal "prod", travel.reload.rabbitmq_environment
  end

  test "normalizes the rabbitmq environment case and whitespace" do
    travel = create_travel(arrival_tick: 100, rabbitmq_environment: "  DEV \n")

    assert_equal "dev", travel.reload.rabbitmq_environment
  end

  test "treats a blank rabbitmq environment as production" do
    travel = create_travel(arrival_tick: 100, rabbitmq_environment: "  ")

    assert_equal "prod", travel.reload.rabbitmq_environment
  end

  test "rejects an unsupported rabbitmq environment" do
    travel = ShipTravel.new(
      user_ship: create_user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: 100,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      rabbitmq_environment: "staging"
    )

    refute travel.valid?
    assert_includes travel.errors[:rabbitmq_environment], "must be one of: prod, dev"
  end

  test "interdiction and resume preserve the rabbitmq environment" do
    travel = create_travel(arrival_tick: 100, rabbitmq_environment: "dev")

    travel.interdict!(95)
    assert_equal "dev", travel.reload.rabbitmq_environment

    travel.resume!(96)
    assert_equal "dev", travel.reload.rabbitmq_environment
  end

  test 'orbital activation leaves saved journeys and interdiction lifecycle unchanged' do
    activation=OrbitalState.catalog.data.fetch('clock').fetch('orbital_progression').first.fetch('activation_tick')
    active=create_travel(arrival_tick:activation+10)
    paused=create_travel(arrival_tick:0,is_paused:true)
    before=[active,paused].map(&:attributes)
    [activation-1,activation,activation+1].each { |tick| OrbitalState.snapshot(tick:tick) }
    assert_equal before,[active,paused].map { |trip| trip.reload.attributes }
    assert_equal 0,ShipTravel.cleanup_stale_after_arrival!(activation+1)
    active.interdict!(activation+2)
    assert_equal 8,active.reload.remaining_ticks_from_arrival
    assert_equal 0,active.arrival_tick
    active.resume!(activation+4)
    assert_equal activation+12,active.reload.arrival_tick
    assert_equal 8,active.total_duration_ticks # Existing resume contract stores remaining duration.
    assert paused.reload.is_paused
    assert_equal 0,paused.arrival_tick
  end

  private

  def create_user_ship(status: "docked")
    UserShip.create!(
      user: @user,
      ship: @ship,
      guid: SecureRandom.uuid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: status
    )
  end

  def create_travel(user_ship: create_user_ship, arrival_tick:, is_paused: false, completed_at_tick: nil, rabbitmq_environment: nil)
    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: arrival_tick,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      is_paused: is_paused,
      completed_at_tick: completed_at_tick,
      rabbitmq_environment: rabbitmq_environment
    )
  end
end
