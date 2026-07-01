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

  test "resolves unqualified gateway names within a star system" do
    pyro_nyx_gateway = Location.create!(
      name: "Nyx Gateway (Pyro)",
      nickname: "Nyx Gateway (Pyro)",
      space_station_name: "Nyx Gateway (Pyro)",
      orbit_name: "Nyx Gateway (Pyro system)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )
    stanton_nyx_gateway = Location.create!(
      name: "Nyx Gateway (Stanton)",
      nickname: "Nyx Gateway (Stanton)",
      space_station_name: "Nyx Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
    )

    assert_equal pyro_nyx_gateway, LocationResolver.find_in_star_system!(
      input_name: "Nyx Gateway",
      star_system_name: "Pyro"
    )
    assert_equal stanton_nyx_gateway, LocationResolver.find_in_star_system!(
      input_name: "Nyx Gateway",
      star_system_name: "Stanton"
    )
  end

  test "resolves full parenthetical gateway names within a star system" do
    location = Location.create!(
      name: "Pyro Gateway (Stanton)",
      nickname: "Pyro Gateway (Stanton)",
      space_station_name: "Pyro Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton",
      is_available: true,
      is_visible: true
    )

    assert_equal location, LocationResolver.find_in_star_system!(
      input_name: "Pyro Gateway (Stanton)",
      star_system_name: "Stanton"
    )
  end

  test "uses orbit name normalization for gateway aliases" do
    location = Location.create!(
      name: "Nyx Gateway (Pyro)",
      orbit_name: "Nyx Gateway (Pyro system)",
      classification: "space_station",
      star_system_name: "Pyro",
      is_available: true,
      is_visible: true
    )

    assert_equal location, LocationResolver.find_in_star_system!(
      input_name: "Nyx Gateway",
      star_system_name: "Pyro"
    )
  end

  test "infers a unique star system where from and to names both exist" do
    terra_gateway_stanton = Location.create!(
      name: "Terra Gateway (Stanton)",
      nickname: "Terra Gateway (Stanton)",
      space_station_name: "Terra Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton"
    )
    pyro_gateway_stanton = Location.create!(
      name: "Pyro Gateway (Stanton)",
      nickname: "Pyro Gateway (Stanton)",
      space_station_name: "Pyro Gateway (Stanton)",
      classification: "space_station",
      star_system_name: "Stanton"
    )
    Location.create!(
      name: "Terra Gateway (Pyro)",
      nickname: "Terra Gateway (Pyro)",
      space_station_name: "Terra Gateway (Pyro)",
      classification: "space_station",
      star_system_name: "Pyro"
    )

    match = LocationResolver.resolve_pair_in_star_system(
      from_name: "terra gateway",
      to_name: "pyro gateway"
    )

    assert_equal "Stanton", match.star_system_name
    assert_equal terra_gateway_stanton, match.from_location
    assert_equal pyro_gateway_stanton, match.to_location
  end
end
