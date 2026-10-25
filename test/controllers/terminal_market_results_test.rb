require "test_helper"
require_relative "../support/terminal_market_fixtures"

class TerminalMarketResultsTest < ActionDispatch::IntegrationTest
  include TerminalMarketFixtures
  setup { terminal_market_setup }

  test "groups render both headings correct quotes empty states and unique overlap IDs" do
    both = terminal_offer(price_buy: 12.34, price_sell: 56.78, inventory: 0)
    terminal_offer(status_buy: 1, commodity_name: "Missing Quote")
    get star_trader_market_path, params: {terminal_api_id: @terminal.api_id}, headers: {"Turbo-Frame"=>"market_results"}
    assert_response :success
    assert_select '[data-market-group="buy"] h3', text: "Buy"
    assert_select '[data-market-group="sell"] h3', text: "Sell"
    assert_operator response.body.index('data-market-group="buy"'), :<, response.body.index('data-market-group="sell"')
    assert_select "#market_buy_row_#{both.id}", count: 1
    assert_select "#market_sell_row_#{both.id}", count: 1
    assert_includes response.body, "aUEC 12.34"
    assert_includes response.body, "aUEC 56.78"
    assert_includes response.body, "No current quote"
    assert_includes response.body, "Out of stock"
    assert_select '[data-group-count="buy"]', text: "2"
    assert_select '[data-group-count="sell"]', text: "1"
  end

  test "all terminal-applied invalid or empty states keep both groups and never broaden" do
    terminal_offer(price_buy: 1)
    ["29junk", ["900029"], "2147483648", "999999"].each do |id|
      get star_trader_market_path, params: {terminal_api_id: id}, headers: {"Turbo-Frame"=>"market_results"}
      assert_response :success
      assert_select '[role="alert"]'
      assert_select '[data-market-group]', count: 2
      assert_select '[data-facility-id]', count: 0
    end
    ProductionFacility.delete_all
    get star_trader_market_path, params: {terminal_api_id: @terminal.api_id}
    assert_response :success
    assert_includes response.body, @terminal.name
    assert_select '[data-market-group]', count: 2
  end

  test "full independent counts pages and applied links retain every filter" do
    61.times { |n| terminal_offer(commodity_name: "Ore #{n}", price_buy: 1, price_sell: 2) }
    get star_trader_market_path, params: {terminal_api_id: @terminal.api_id, buy_page: 2, sell_page: 1, sort: "commodity", direction: "asc", q: "Ore"}
    assert_response :success
    assert_select '[data-group-count="buy"]', text: "61"
    assert_select '[data-group-count="sell"]', text: "61"
    assert_select '[data-market-group="buy"] article', count: 11
    assert_select '[data-market-group="sell"] article', count: 50
    assert_select 'a[aria-label="Next Sell page"]' do |links|
      query = Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)
      assert_equal "2", query["buy_page"]
      assert_equal "2", query["sell_page"]
      assert_equal "Ore", query["q"]
      assert_equal @terminal.api_id.to_s, query["terminal_api_id"]
    end
    assert_select 'a[aria-label="Next Sell page"][data-turbo-frame="_top"]', count: 1
    assert_select 'a[data-turbo-action="advance"]', count: 0
    assert_select 'form[data-controller="market-filters"]', count: 1
    assert_select '#market_terminal_search', count: 1
    assert_select 'form[data-controller="market-filters"][data-turbo-frame]', count: 0
  end
end
