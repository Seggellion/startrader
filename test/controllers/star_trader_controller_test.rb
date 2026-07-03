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
      local_sell_price: 42,
      local_buy_price: 117,
      price_sell: 40,
      price_buy: 110,
      status_sell: 1,
      status_buy: 1
    )

    get root_path

    assert_response :success
    assert_includes response.body, "Buy from terminal"
    assert_includes response.body, "Sell to terminal"
    assert_includes response.body, "Player buy price"
    assert_includes response.body, "Player sell price"
    assert_includes response.body, "Player can buy (terminal sells)"
    assert_includes response.body, "Player can sell (terminal buys)"
    assert_includes response.body, "Best player buy"
    assert_includes response.body, "Best player sell"
    assert_no_match(/>Buy<\/(?:span|dt)>/, response.body)
    assert_no_match(/>Sell<\/(?:span|dt)>/, response.body)
  end

  test "player buy filter and sort use terminal sell price" do
    create_facility(commodity_name: "Cheap Terminal Sell", local_sell_price: 18, status_sell: 1)
    create_facility(commodity_name: "Expensive Terminal Sell", local_sell_price: 42, status_sell: 1)
    create_facility(commodity_name: "Terminal Buy Only", local_buy_price: 99, status_buy: 1)

    get star_trader_market_path,
      params: { trade_mode: "buy", sort: "buy_price", direction: "asc" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_includes response.body, "Cheap Terminal Sell"
    assert_includes response.body, "Expensive Terminal Sell"
    assert_not_includes response.body, "Terminal Buy Only"
    assert_operator response.body.index("Cheap Terminal Sell"), :<, response.body.index("Expensive Terminal Sell")
  end

  test "player sell filter uses terminal buy price" do
    create_facility(commodity_name: "Terminal Sell Only", local_sell_price: 18, status_sell: 1)
    create_facility(commodity_name: "Terminal Buy From Player", local_buy_price: 99, status_buy: 1)

    get star_trader_market_path,
      params: { trade_mode: "sell", sort: "sell_price", direction: "desc" },
      headers: { "Turbo-Frame" => "market_results" }

    assert_response :success
    assert_includes response.body, "Terminal Buy From Player"
    assert_not_includes response.body, "Terminal Sell Only"
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
      scu_buy: 250,
      scu_sell: 0,
      scu_sell_stock: 100,
      commodity_name: "Test Commodity",
      location_name: @location.name
    }.merge(attributes))
  end
end
