require "test_helper"

class PlanetPositionCalculatorTest < ActiveSupport::TestCase
  setup do
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Shard.delete_all
    Ship.delete_all
    Location.delete_all
    Setting.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    Setting.create!(key: "hours_per_tick", value: "1", setting_type: "text")
    Tick.create!(current_tick: 10, sequence: 1)

    @star = Location.create!(
      name: "Stanton",
      classification: "star",
      mass: 1.9885e30
    )

    @planet = create_planet(name: "ArcCorp", periapsis: 10.0, apoapsis: 12.0)
    @other_planet = create_planet(name: "Hurston", periapsis: 16.0, apoapsis: 18.0)
    @moon = Location.create!(
      name: "Lyria",
      classification: "moon",
      parent_name: @planet.name,
      star_system_name: @star.name,
      mass: 7.35e22,
      periapsis: 0.35,
      apoapsis: 0.42
    )
  end

  test "calculate_position uses simulated seconds per tick and does not require legacy constant" do
    gateway = Location.create!(
      name: "Pyro Gateway",
      classification: "space_station",
      parent_name: @star.name,
      periapsis: 24.0,
      apoapsis: 24.0
    )

    [@planet, @moon, gateway].each do |location|
      position = nil

      assert_nothing_raised do
        position = PlanetPositionCalculator.calculate_position(location, Tick.current)
      end

      assert_kind_of Numeric, position[:x]
      assert_kind_of Numeric, position[:y]
    end
  end

  test "changing hours_per_tick changes orbital position at the same tick" do
    one_hour_position = PlanetPositionCalculator.calculate_position(@planet, 10)

    Setting.find_by!(key: "hours_per_tick").update!(value: "2")
    two_hour_position = PlanetPositionCalculator.calculate_position(@planet, 10)

    assert_operator distance_between(one_hour_position, two_hour_position), :>, 0.0001
  end

  test "travel creation uses orbital distance without legacy tick constant" do
    from_city = Location.create!(
      name: "Area18",
      classification: "city",
      parent_name: @planet.name,
      star_system_name: @star.name
    )
    to_city = Location.create!(
      name: "Lorville",
      classification: "city",
      parent_name: @other_planet.name,
      star_system_name: @star.name
    )
    user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    user_ship = UserShip.create!(
      user: user,
      ship: ship,
      guid: "ship-guid",
      ship_slug: ship.slug,
      location: from_city,
      total_scu: ship.scu,
      used_scu: 0,
      status: "docked"
    )

    travel = nil
    assert_nothing_raised do
      travel = TravelService.new(
        user_ship: user_ship,
        to_location: to_city,
        travel_guid: "travel-guid",
        start_tick: Tick.current
      ).call
    end

    assert_equal Tick.current, travel.departure_tick
    assert_operator travel.arrival_tick, :>, travel.departure_tick
  end

  private

  def create_planet(name:, periapsis:, apoapsis:)
    Location.create!(
      name: name,
      classification: "planet",
      parent_name: @star.name,
      star_system_name: @star.name,
      mass: 5.972e24,
      periapsis: periapsis,
      apoapsis: apoapsis
    )
  end

  def distance_between(first, second)
    Math.sqrt((second[:x] - first[:x])**2 + (second[:y] - first[:y])**2)
  end
end
