require "test_helper"
require_relative "../support/orbital_fixtures"

class PlanetPositionCalculatorTest < ActiveSupport::TestCase
  include OrbitalFixtures
  setup do
    seed_orbital_catalog
    @planet = Location.find_by!(name: "Hurston")
  end
  test "physical position uses explicit catalog radius without rendering scale" do
    position = PlanetPositionCalculator.calculate_position(@planet, 0)
    assert_in_delta 13, position[:x], 1e-9
    assert_in_delta 0, position[:y], 1e-9
    assert_equal 0, position[:z]
  end
  test "changing legacy hours setting does not rewrite the catalog anchor" do
    before = PlanetPositionCalculator.calculate_position(@planet, 10)
    Setting.create!(key: "hours_per_tick", value: "2", setting_type: "text")
    assert_equal before, PlanetPositionCalculator.calculate_position(@planet, 10)
    refute_equal before, PlanetPositionCalculator.calculate_position(@planet, 11)
  end
  test "unmeasured nested bodies are unavailable instead of invented orbits" do
    moon = Location.create!(name: "Arial", classification: "moon", parent_name: "Hurston", star_system_name: "Stanton", periapsis: 50, apoapsis: 50)
    assert_raises(Orbital::Unavailable) { PlanetPositionCalculator.calculate_position(moon, 0) }
  end
end
