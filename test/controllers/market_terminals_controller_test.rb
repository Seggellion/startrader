require "test_helper"
require_relative "../support/terminal_market_fixtures"

class MarketTerminalsControllerTest < ActionDispatch::IntegrationTest
  include TerminalMarketFixtures
  setup { terminal_market_setup; terminal_offer(price_buy: 10) }

  test "strict shapes limits token budget and no catalog preload" do
    get market_terminals_path
    assert_response :success
    assert_equal [], response.parsed_body["results"]
    get market_terminals_path, params: {q: ["Shared"]}
    assert_response :bad_request
    get market_terminals_path, params: {q: "a " * 6}
    assert_response :unprocessable_entity
    get market_terminals_path, params: {q: "a" * 101}
    assert_response :unprocessable_entity
    get market_terminals_path, params: {q: "Shared", star_system: ["Stanton"]}
    assert_response :bad_request
  end

  test "context tokens AND optional system and external identity remain exact" do
    get market_terminals_path, params: {q: "Shared Hurston"}
    assert_response :success
    row = response.parsed_body["results"].sole
    assert_equal @terminal.api_id, row["terminal_api_id"]
    assert_not_equal @terminal.id, row["terminal_api_id"]
    assert_includes row["context"], "Stanton"
    assert_equal %w[terminal_api_id name code nickname location_name star_system_name context].sort, row.keys.sort
    get market_terminals_path, params: {q: "Shared", star_system: "Unknown"}
    assert_equal [], response.parsed_body["results"]
    get market_terminals_path, params: {q: "Shared nonexistent"}
    assert_equal [], response.parsed_body["results"]
    get market_terminals_path, params: {q: "Sh%"}
    assert_equal [], response.parsed_body["results"]
  end

  test "caps matched options ignores caller limit and excludes unsupported terminals" do
    @terminal.update!(name: "Shared")
    25.times do |n|
      terminal = Terminal.create!(api_id: 910000 + n, name: "Shared %02d" % n, code: "SHARED", location_name: @host.name)
      terminal_offer(id_terminal: terminal.api_id, price_buy: 2)
    end
    Terminal.create!(api_id: 920000, name: "Shared no market", location_name: @host.name)
    Terminal.create!(api_id: 920001, name: "Shared orphan", location_name: "Unknown")
    get market_terminals_path, params: {q: "Shared", limit: 10000}
    assert_response :success
    body = response.parsed_body
    assert_equal 20, body["results"].size
    assert_equal true, body["has_more"]
    assert_operator response.body.bytesize, :<=, 20 * 1024
    refute body["results"].any? { |r| r["terminal_api_id"] >= 920000 }
    assert_equal @terminal.api_id, body["results"].first["terminal_api_id"], "exact name ranks first"
  end

  test "same names and codes remain separate with optional host flags" do
    other = Terminal.create!(api_id: 900031, name: @terminal.name, code: @terminal.code, location_name: @host.name)
    terminal_offer(id_terminal: other.api_id, status_buy: 1)
    get market_terminals_path, params: {q: "SHARED"}
    assert_equal [@terminal.api_id, other.api_id], response.parsed_body["results"].map { |r| r["terminal_api_id"] }
  end
end
