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

  test "cleanup does not remove current tick arrival" do
    travel = create_travel(arrival_tick: 105)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove future travel" do
    travel = create_travel(arrival_tick: 106)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove paused interdicted travel" do
    travel = create_travel(arrival_tick: 0, is_paused: true)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
  end

  test "cleanup does not remove completed travel" do
    travel = create_travel(arrival_tick: 100, completed_at_tick: 100)

    assert_equal 0, ShipTravel.cleanup_stale_after_arrival!(105)
    assert ShipTravel.exists?(travel.id)
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

  def create_travel(user_ship: create_user_ship, arrival_tick:, is_paused: false, completed_at_tick: nil)
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
      completed_at_tick: completed_at_tick
    )
  end
end
