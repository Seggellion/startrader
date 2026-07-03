require "test_helper"

class StarTraderControllerTest < ActionDispatch::IntegrationTest
  setup do
    ProductionFacility.delete_all
    Terminal.delete_all
    Location.delete_all
    Commodity.delete_all
    Tick.delete_all

    Tick.create!(current_tick: 12, sequence: 1)

    @location = Location.create!(
      name: "Baijini Point",
      classification: "space_station",
      star_system_name: "Stanton",
      planet_name: "ArcCorp",
      has_trade_terminal: true
    )
  end

  test "main page uses player perspective price labels" do
    create_facility(
      commodity_name: "Agricium",
      local_buy_price: 42,
      local_sell_price: 117,
      price_buy: 40,
      price_sell: 110,
      status_buy: 1,
      status_sell: 1
    )

    get root_path

    assert_response :success
    assert_includes response.body, "Player buy price"
    assert_includes response.body, "Player sell price"
    assert_includes response.body, "Player can buy"
    assert_includes response.body, "Player can sell"
    assert_includes response.body, "Best player buy"
    assert_includes response.body, "Best player sell"
    assert_no_match(/>Buy<\/(?:span|dt)>/, response.body)
    assert_no_match(/>Sell<\/(?:span|dt)>/, response.body)
  end

  test "hdms bezdek laranite pattern is player can buy only" do
    facility = create_facility(
      facility_name: "HDMS-Bezdek",
      commodity_name: "Laranite",
      production_rate: 5,
      consumption_rate: 0,
      inventory: 150,
      max_inventory: 5000,
      local_buy_price: 8678.52,
      local_sell_price: nil,
      price_buy: 7541,
      price_sell: 0,
      scu_buy: 1050,
      scu_sell: 0,
      scu_sell_stock: 0,
      status_buy: 7,
      status_sell: 0,
      terminal_name: "HDMS-Bezdek",
      location_name: "HDMS-Bezdek"
    )

    assert facility.player_can_buy?
    refute facility.player_can_sell?
    assert_equal 8678.52.to_d, facility.player_buy_price
    assert_equal 0.to_d, facility.player_sell_price
  end

  test "player buy filter and sort use buy-side fields" do
    create_facility(commodity_name: "Cheap Buy Side", local_buy_price: 18, status_buy: 1)
    create_facility(commodity_name: "Expensive Buy Side", local_buy_price: 42, status_buy: 1)
    create_facility(commodity_name: "Sell Side Only", local_sell_price: 99, status_sell: 1)

    get star_trader_market_path,
      params: { trade_mode: "buy", sort: "buy_price", direction: "asc" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_includes response.body, "Cheap Buy Side"
    assert_includes response.body, "Expensive Buy Side"
    assert_not_includes response.body, "Sell Side Only"
    assert_operator response.body.index("Cheap Buy Side"), :<, response.body.index("Expensive Buy Side")
  end

  test "player sell filter uses sell-side fields" do
    create_facility(commodity_name: "Buy Side Only", local_buy_price: 18, status_buy: 1)
    create_facility(commodity_name: "Sell Side Active", local_sell_price: 99, status_sell: 1)

    get star_trader_market_path,
      params: { trade_mode: "sell", sort: "sell_price", direction: "desc" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_includes response.body, "Sell Side Active"
    assert_not_includes response.body, "Buy Side Only"
  end

  test "hdms bezdek laranite appears in player can buy filter only" do
    create_facility(
      facility_name: "HDMS-Bezdek",
      commodity_name: "Laranite",
      production_rate: 5,
      consumption_rate: 0,
      inventory: 150,
      max_inventory: 5000,
      local_buy_price: 8678.52,
      local_sell_price: nil,
      price_buy: 7541,
      price_sell: 0,
      scu_buy: 1050,
      scu_sell: 0,
      scu_sell_stock: 0,
      status_buy: 7,
      status_sell: 0,
      terminal_name: "HDMS-Bezdek",
      location_name: "HDMS-Bezdek"
    )

    get star_trader_market_path,
      params: { trade_mode: "buy" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_includes response.body, "Laranite"
    assert_includes response.body, "aUEC 8,678.52"

    get star_trader_market_path,
      params: { trade_mode: "sell" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_not_includes response.body, "Laranite"
  end

  private

  def create_facility(attributes = {})
    Commodity.find_or_create_by!(name: attributes.fetch(:commodity_name, "Test Commodity"))

    ProductionFacility.create!({
      facility_name: "Trade Terminal",
      production_rate: 0,
      consumption_rate: 0,
      inventory: 100,
      max_inventory: 500,
      local_buy_price: 0,
      local_sell_price: 0,
      price_buy: 0,
      price_sell: 0,
      price_buy_avg: 0,
      price_sell_avg: 0,
      status_buy: 0,
      status_sell: 0,
      scu_buy: 0,
      scu_sell: 0,
      scu_sell_stock: 0,
      commodity_name: "Test Commodity",
      location_name: @location.name
    }.merge(attributes))
  end
end
