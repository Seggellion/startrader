require "test_helper"
require_relative "../support/terminal_market_fixtures"

class MarketQueryTest < ActiveSupport::TestCase
  include TerminalMarketFixtures
  setup { terminal_market_setup }

  test "external identity isolates siblings despite equal names and codes and missing commodity" do
    other = Terminal.create!(api_id: 900030, name: @terminal.name, code: @terminal.code, location_name: @host.name)
    mine = terminal_offer(price_buy: 12.34, commodity_name: "Sadaryx")
    terminal_offer(id_terminal: other.api_id, price_buy: 99)
    result = MarketQuery.new(terminal_api_id: @terminal.api_id).call
    assert_not_equal @terminal.id, @terminal.api_id
    assert_equal [mine.id], result.buy.rows.map(&:id)
    assert_nil result.buy.rows.first.commodity
    assert_equal 12.34.to_d, result.buy.rows.first.player_buy_price
    assert result.sell.rows.empty?
  end

  test "invalid terminal never broadens and known empty identity survives" do
    terminal_offer(price_buy: 1)
    ["0", "-1", "29junk", "2147483648", ["900029"], {id: "900029"}, "999999"].each do |id|
      result = MarketQuery.new(terminal_api_id: id).call
      assert result.grouped?, id.inspect
      assert result.selection_error, id.inspect
      assert_empty result.rows
    end
    ProductionFacility.delete_all
    result = MarketQuery.new(terminal_api_id: @terminal.api_id).call
    assert_equal @terminal, result.terminal
    assert_nil result.selection_error
    assert_equal 0, result.buy.total_count
  end

  test "full action scopes count overlap before independent pagination and clamp" do
    rows = (1..61).map { |n| terminal_offer(commodity_name: "Ore %03d" % n, price_buy: 10, price_sell: 12) }
    result = MarketQuery.new(terminal_api_id: @terminal.api_id, sort: "commodity", direction: "asc", buy_page: 2, sell_page: 1).call
    assert_equal 61, result.buy.total_count
    assert_equal 61, result.sell.total_count
    assert_equal 11, result.buy.rows.length
    assert_equal 50, result.sell.rows.length
    assert_equal rows[50].id, result.buy.rows.first.id
    result = MarketQuery.new(terminal_api_id: @terminal.api_id, buy_page: 999, sell_page: "junk").call
    assert_equal 2, result.buy.page
    assert_equal 1, result.sell.page
  end

  test "same-row Both and missing quote support remain exact" do
    both = terminal_offer(status_buy: 1, price_sell: 50)
    terminal_offer(price_buy: 12)
    terminal_offer(price_sell: 14)
    %w[buy sell both].each do |mode|
      result = MarketQuery.new(terminal_api_id: @terminal.api_id, trade_mode: mode).call
      assert_includes result.buy.rows.map(&:id), both.id
      assert_includes result.sell.rows.map(&:id), both.id
      if mode == "both"
        assert_equal [both.id], result.buy.rows.map(&:id)
        assert_equal [both.id], result.sell.rows.map(&:id)
      end
    end
  end

  test "all restrictive filters intersect and system mismatch is explicit" do
    commodity = Commodity.create!(name: "Specific Ore")
    terminal_offer(commodity_name: commodity.name, price_buy: 10)
    base = {terminal_api_id: @terminal.api_id}
    assert_equal 1, MarketQuery.new(base.merge(commodity_id: commodity.id, q: "Specific", location_type: "city")).call.buy.total_count
    [:q, :location_type].each do |key|
      assert_equal 0, MarketQuery.new(base.merge(key => "missing")).call.buy.total_count
    end
    result = MarketQuery.new(base.merge(star_system: "Pyro")).call
    assert result.warning
    assert_equal 0, result.buy.total_count
  end

  test "negative local uses displayed positive imported fallback and no quote sorts last" do
    cheap = terminal_offer(price_buy: 5, local_buy_price: -99)
    costly = terminal_offer(price_buy: 10)
    unavailable = terminal_offer(status_buy: 1)
    result = MarketQuery.new(terminal_api_id: @terminal.api_id, sort: "buy_price", direction: "asc").call
    assert_equal [cheap.id, costly.id, unavailable.id], result.buy.rows.map(&:id)
    assert_equal 5.to_d, result.buy.rows.first.player_buy_price
  end

  test "legacy remains ungrouped and snapshot preloads associations with bounded queries" do
    Commodity.create!(name: "Test Ore")
    51.times { terminal_offer(price_buy: 1, price_sell: 2) }
    result = MarketQuery.new(page: 2).call
    refute result.grouped?
    assert_equal 51, result.legacy.total_count
    assert_equal 1, result.legacy.rows.size
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) {
      statements << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] || payload[:sql].match?(/\A(?:BEGIN|COMMIT|SAVEPOINT|RELEASE|SET )/)
    }
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        r = MarketQuery.new(terminal_api_id: @terminal.api_id).call
        (r.buy.rows + r.sell.rows).each { |row| row.commodity; row.location }
      end
    end
    assert_operator statements.size, :<=, 8, statements.join("\n")
  end
end
