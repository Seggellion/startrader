require "test_helper"

class Api::CommoditiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ProductionFacility.delete_all
    Terminal.delete_all
    Location.delete_all
    Commodity.delete_all

    @area18 = Location.create!(
      name: "Area18",
      classification: "city",
      star_system_name: "Stanton",
      planet_name: "ArcCorp",
      has_trade_terminal: true
    )
    @orison = Location.create!(
      name: "Orison",
      classification: "city",
      star_system_name: "Stanton",
      planet_name: "Crusader",
      has_trade_terminal: true
    )
    @tdd = Terminal.create!(api_id: 10_001, name: "TDD", location_name: @area18.name)
    @admin = Terminal.create!(api_id: 10_002, name: "Admin", location_name: @orison.name)
  end

  test "commodities index allows cors requests from starbitizen origin" do
    get "/api/commodities", headers: { "Origin" => "https://starbitizen.com" }

    assert_response :success
    assert_equal "https://starbitizen.com", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Vary"], "Origin"
  end

  test "commodities index allows cors requests from maidenbot origin" do
    get "/api/commodities", headers: { "Origin" => "https://maidenbot.com" }

    assert_response :success
    assert_equal "https://maidenbot.com", response.headers["Access-Control-Allow-Origin"]
  end

  test "commodities index does not allow unlisted cors origins" do
    get "/api/commodities", headers: { "Origin" => "https://example.com" }

    assert_response :success
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "commodities index handles starbitizen cors preflight" do
    options "/api/commodities", headers: {
      "Origin" => "https://starbitizen.com",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "Content-Type"
    }

    assert_response :success
    assert_equal "https://starbitizen.com", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Allow-Methods"], "GET"
    assert_includes response.headers["Access-Control-Allow-Headers"], "Content-Type"
  end

  test "returns JSON API commodity resources from production facilities" do
    Commodity.create!(name: "Agricium", is_illegal: true)
    facility = create_facility(
      api_id: 3468,
      id_terminal: @tdd.api_id,
      commodity_name: "Agricium",
      local_buy_price: 2539.45,
      price_buy: 2400,
      status_buy: 1,
      updated_at: Time.utc(2026, 6, 24, 7, 8, 58, 20_000)
    )

    get "/api/commodities"

    assert_response :success
    assert_kind_of Array, response_json["data"]
    assert_equal 1, response_json["data"].size

    item = response_json["data"].first
    assert_equal "3468", item["id"]
    assert_equal "commodities", item["type"]
    assert_equal "https://ctd.altama.energy/commodities/3468", item.dig("links", "self")
    assert_equal "Agricium", item.dig("attributes", "name")
    assert_equal "Area18 - TDD", item.dig("attributes", "location")
    assert_equal 2539, item.dig("attributes", "buy")
    assert_equal 0, item.dig("attributes", "sell")
    assert_equal true, item.dig("attributes", "vice")
    assert_equal facility.updated_at.iso8601(3), item.dig("attributes", "updated-at")
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, item.dig("attributes", "updated-at"))
    assert_equal false, item.dig("attributes", "out-of-date")
  end

  test "excludes unavailable or unusable rows" do
    create_facility(commodity_name: nil, local_buy_price: 10, status_buy: 1)
    create_facility(commodity_name: "No Context", location_name: nil, terminal_name: nil, id_terminal: nil, local_buy_price: 10)
    create_facility(commodity_name: "No Price", local_buy_price: 0, price_buy: 0, local_sell_price: 0, price_sell: 0, status_buy: 1, status_sell: 1)
    create_facility(commodity_name: "Sell Status Off", local_sell_price: 10, status_sell: 0, scu_sell_stock: 0, scu_sell: 0, production_rate: 0, inventory: 0)
    create_facility(commodity_name: "Available", local_buy_price: 99, status_buy: 1)

    get "/api/commodities"

    assert_response :success
    names = response_json["data"].map { |item| item.dig("attributes", "name") }
    assert_equal ["Available"], names
  end

  test "includes buy only sell only and both sided production facility rows" do
    create_facility(commodity_name: "Buy Only", local_buy_price: 11, status_buy: 1)
    create_facility(commodity_name: "Sell Only", local_sell_price: 22, status_sell: 1)
    create_facility(commodity_name: "Both", local_buy_price: 33, status_buy: 1, local_sell_price: 44, status_sell: 1)

    get "/api/commodities"

    assert_response :success
    records = response_json["data"].index_by { |item| item.dig("attributes", "name") }

    assert_equal 11, records.fetch("Buy Only").dig("attributes", "buy")
    assert_equal 0, records.fetch("Buy Only").dig("attributes", "sell")
    assert_equal 0, records.fetch("Sell Only").dig("attributes", "buy")
    assert_equal 22, records.fetch("Sell Only").dig("attributes", "sell")
    assert_equal 33, records.fetch("Both").dig("attributes", "buy")
    assert_equal 44, records.fetch("Both").dig("attributes", "sell")
  end

  test "uses production facilities as source of truth and does not require commodity records" do
    Commodity.create!(name: "Commodity Table Only", is_illegal: true)
    facility = create_facility(
      commodity_name: "Facility Only",
      local_buy_price: 123,
      status_buy: 1,
      api_id: nil
    )

    get "/api/commodities"

    assert_response :success
    names = response_json["data"].map { |item| item.dig("attributes", "name") }
    assert_equal ["Facility Only"], names
    assert_equal facility.id.to_s, response_json.dig("data", 0, "id")
    assert_equal false, response_json.dig("data", 0, "attributes", "vice")
  end

  test "marks records older than thirty days as out of date" do
    create_facility(commodity_name: "Fresh", local_buy_price: 100, status_buy: 1, updated_at: Time.current)
    create_facility(commodity_name: "Stale", local_buy_price: 200, status_buy: 1, updated_at: 31.days.ago)

    get "/api/commodities"

    assert_response :success
    records = response_json["data"].index_by { |item| item.dig("attributes", "name") }
    assert_equal false, records.fetch("Fresh").dig("attributes", "out-of-date")
    assert_equal true, records.fetch("Stale").dig("attributes", "out-of-date")
  end

  test "sorts records by location terminal context and commodity name" do
    create_facility(commodity_name: "Zeta", location_name: @orison.name, terminal_name: @admin.name, id_terminal: @admin.api_id, local_buy_price: 1)
    create_facility(commodity_name: "Beta", location_name: @area18.name, terminal_name: @tdd.name, id_terminal: @tdd.api_id, local_buy_price: 1)
    create_facility(commodity_name: "Alpha", location_name: @area18.name, terminal_name: @tdd.name, id_terminal: @tdd.api_id, local_buy_price: 1)

    get "/api/commodities"

    assert_response :success
    assert_equal(
      ["Alpha", "Beta", "Zeta"],
      response_json["data"].map { |item| item.dig("attributes", "name") }
    )
    assert_equal(
      ["Area18 - TDD", "Area18 - TDD", "Orison - Admin"],
      response_json["data"].map { |item| item.dig("attributes", "location") }
    )
  end

  private

  def create_facility(attributes = {})
    now = attributes.delete(:updated_at) || Time.current

    facility = ProductionFacility.new({
      facility_name: "Test Facility",
      production_rate: 0,
      consumption_rate: 0,
      inventory: 0,
      max_inventory: 100,
      local_buy_price: 0,
      local_sell_price: 0,
      price_buy: 0,
      price_sell: 0,
      status_buy: 0,
      status_sell: 0,
      scu_buy: 0,
      scu_sell: 0,
      scu_sell_stock: 0,
      commodity_name: "Test Commodity",
      location_name: @area18.name,
      terminal_name: @tdd.name,
      id_terminal: @tdd.api_id
    }.merge(attributes))

    facility.save!
    facility.update_columns(created_at: now, updated_at: now)
    facility
  end

  def response_json
    JSON.parse(response.body)
  end
end
