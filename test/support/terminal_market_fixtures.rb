require "minitest/mock"

module TerminalMarketFixtures
  def terminal_market_setup
    ProductionFacility.without_market_broadcasts { ProductionFacility.delete_all }
    Terminal.delete_all
    Commodity.delete_all
    # Avoid deleting orbital catalog identities used by other isolated tests.
    @host = Location.find_or_create_by!(name: "Terminal Test Host") do |host|
      host.classification = "city"
      host.star_system_name = "Stanton"
      host.planet_name = "Hurston"
    end
    @terminal = Terminal.create!(api_id: 900029, name: "Shared Terminal", code: "SHARED", location_name: @host.name)
  end

  def terminal_offer(attrs = {})
    defaults = {
      facility_name: @terminal.name, terminal_name: @terminal.name, id_terminal: @terminal.api_id,
      location_name: @host.name, commodity_name: "Test Ore", production_rate: 0, consumption_rate: 0,
      inventory: 10, max_inventory: 100, price_buy: 0, local_buy_price: 0, price_sell: 0, local_sell_price: 0,
      status_buy: 0, status_sell: 0, scu_buy: 0, scu_sell: 0, scu_sell_stock: 0
    }
    ProductionFacility.without_market_broadcasts { ProductionFacility.create!(defaults.merge(attrs)) }
  end
end
