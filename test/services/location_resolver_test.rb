require "test_helper"

class LocationResolverTest < ActiveSupport::TestCase
  setup do
    Location.delete_all

    @shubin_22 = Location.create!(
      name: "Shubin Mining Facility SM0-22",
      classification: "outpost",
      star_system_name: "Stanton",
      planet_name: "MicroTech"
    )

    Location.create!(
      name: "Shubin Mining Facility SM0-18",
      classification: "outpost",
      star_system_name: "Stanton",
      planet_name: "MicroTech"
    )
  end

  test "resolves short facility code from location name" do
    assert_equal @shubin_22, LocationResolver.resolve("SM0-22")
  end

  test "resolves normalized facility code variants from location name" do
    assert_equal @shubin_22, LocationResolver.resolve("SM0 22")
    assert_equal @shubin_22, LocationResolver.resolve("sm022")
  end

  test "resolves nickname-style facility references" do
    assert_equal @shubin_22, LocationResolver.resolve("Shubin 22")
    assert_equal @shubin_22, LocationResolver.resolve("shubin 22")
  end

  test "preserves exact matching against name nickname and code" do
    location = Location.create!(
      name: "Everus Harbor",
      nickname: "Everus",
      code: "EH",
      classification: "space_station",
      star_system_name: "Stanton"
    )

    assert_equal location, LocationResolver.resolve("Everus Harbor")
    assert_equal location, LocationResolver.resolve("everus")
    assert_equal location, LocationResolver.resolve("eh")
  end

  test "preserves trailing facility suffix matching" do
    location = Location.create!(
      name: "Area18",
      classification: "city",
      star_system_name: "Stanton",
      has_trade_terminal: true
    )

    assert_equal location, LocationResolver.resolve("Area18 TDD")
    assert_equal location, LocationResolver.resolve("Area18 admin")
    assert_equal location, LocationResolver.resolve("Area18 trade terminal")
  end

  test "does not resolve unsafe short or noise-only inputs" do
    assert_nil LocationResolver.resolve("22")
    assert_nil LocationResolver.resolve("SM")
    assert_nil LocationResolver.resolve("admin")
    assert_nil LocationResolver.resolve("terminal")
  end
end
