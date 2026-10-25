# Synthetic, loopback-only fixture server for official Google Chrome qualification.
ENV["RAILS_ENV"] = "test"
ENV["TICK_BOOTSTRAP"] = "false"
require_relative "../config/environment"
require_relative "../test/support/no_real_broker"
require_relative "../test/support/terminal_market_fixtures"
require "json"
raise "Dedicated preview DB required" unless ActiveRecord::Base.connection.select_value("SELECT current_database()") == "star_trader_terminal_preview"

if ENV["TERMINAL_FIXTURES"] == "reset"
  ProductionFacility.without_market_broadcasts { ProductionFacility.delete_all }
  Terminal.delete_all
  Commodity.delete_all
  Location.delete_all
  Tick.delete_all
  OrbitalState.catalog.entries.each do |entry|
    Location.create!(name: entry.fetch("name"), api_id: entry.fetch("api_id"),
      classification: entry.fetch("classification"), star_system_name: entry.fetch("system"),
      parent_name: entry["parent"], mass: entry["mass_kg"], periapsis: entry["periapsis_gm"], apoapsis: entry["apoapsis_gm"])
  end
  Tick.create!(current_tick: 701104, sequence: 1)
  host = Location.find_by!(name: "Hurston")
  terminal = Terminal.create!(api_id: 900029, name: "Shared Terminal", code: "SHARED", nickname: "Main market", location_name: host.name)
  other_host = Location.find_by!(name: "Pyro V")
  other = Terminal.create!(api_id: 900030, name: terminal.name, code: terminal.code, nickname: "Other market", location_name: other_host.name)
  fixture = Object.new.extend(TerminalMarketFixtures)
  fixture.instance_variable_set(:@host, host);fixture.instance_variable_set(:@terminal, terminal)
  61.times { |n| fixture.terminal_offer(commodity_name: "Both Ore %03d" % n, price_buy: 10 + n/100.0, price_sell: 12, api_id: 1_000_000+n, date_modified: 1_751_500_000) }
  fixture.terminal_offer(commodity_name: "Buy quote missing", status_buy: 1, inventory: 0, date_modified: 1_751_500_000)
  fixture.terminal_offer(commodity_name: "Sell quote missing", status_sell: 1, inventory: 100, date_modified: 1_751_500_000)
  fixture.terminal_offer(commodity_name: "Sadaryx", price_buy: 5, date_modified: 1_751_500_000)
  fixture.terminal_offer(id_terminal: other.api_id, location_name: other_host.name, commodity_name: "Sibling Only", price_buy: 999)
  828.times do |n|
    t = Terminal.create!(api_id: 910000+n, name: (n.zero? ? "TDD - Trade and Development Division - Common Exchange - New Babbage Hall" : "Catalog terminal %04d" % n), code: (n.zero? ? "LONG" : "CAT%04d" % n), nickname: "Fixture #{n}", location_name: host.name)
    fixture.terminal_offer(id_terminal: t.api_id, commodity_name: "Catalog Ore #{n}", price_buy: 1) if n < 133
  end
  now = Time.current
  (0...2392).each_slice(500) do |batch|
    ProductionFacility.insert_all!(batch.map { |n| {
      api_id: 1_100_000+n, id_terminal: 910000+(n%133), facility_name: "Catalog market", terminal_name: "Catalog market",
      location_name: host.name, commodity_name: "Catalog Ore extra #{n}", price_buy: 1, production_rate: 0, consumption_rate: 0,
      inventory: 10, max_inventory: 100, created_at: now, updated_at: now
    } })
  end
  puts JSON.generate(fixture: "synthetic", terminals: Terminal.count, offers: ProductionFacility.count, terminal_api_id: terminal.api_id, first_offer_id: ProductionFacility.where(id_terminal: terminal.api_id).order(:id).first.id)
end
exit if ENV["TERMINAL_PREPARE_ONLY"] == "true"

# This middleware exists only in the local fixture process, never production routes.
class TerminalFixtureMutation
  def initialize(app); @app=app; end
  def call(env)
    if env["PATH_INFO"] == "/__terminal_test__/mutate" && env["REQUEST_METHOD"] == "POST"
      raise "Wrong fixture DB" unless ActiveRecord::Base.connection.select_value("SELECT current_database()") == "star_trader_terminal_preview"
      row = ProductionFacility.where(id_terminal: 900029).order(:id).first
      mode = Rack::Request.new(env).params["mode"]
      if mode == "shrink"
        ProductionFacility.where(id_terminal: 900029).order(id: :desc).limit(20).delete_all
      elsif mode == "bulk"
        row.update_columns(commodity_name: "Bulk fixture change", updated_at: Time.current)
      else
        row.update_columns(updated_at: Time.current, commodity_name: "Changed by fixture", price_sell: 0, local_sell_price: 0, scu_sell: 0, scu_sell_stock: 0, status_sell: 0, consumption_rate: 0)
      end
      return [200, {"content-type"=>"application/json"}, [JSON.generate(id:row.id, terminal_api_id:row.id_terminal)]]
    end
    @app.call(env)
  end
end
ActionController::Base.allow_forgery_protection = true
require "puma"
server=Puma::Server.new(TerminalFixtureMutation.new(Rails.application))
server.add_tcp_listener("127.0.0.1",8037)
trap("TERM"){server.stop(true)};trap("INT"){server.stop(true)}
puts "Terminal preview ready at http://localhost:8037 (synthetic isolated DB)"
server.run.join
