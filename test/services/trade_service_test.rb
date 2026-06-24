require "test_helper"

class TradeServiceTest < ActiveSupport::TestCase
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    ProductionFacility.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all
    Setting.create!(key: "seconds_per_tick", value: "5", setting_type: "text")

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-guid")
    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @shard_user = ShardUser.create!(
      user: @user,
      shard_id: @shard.id,
      shard_name: @shard.name,
      wallet_balance: 10_000
    )
    @location = Location.create!(
      name: "Test Location",
      classification: "city",
      star_system_name: "Stanton"
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "ship-guid",
      ship_slug: @ship.slug,
      location_name: @location.name,
      total_scu: @ship.scu,
      used_scu: 0
    )
    @terminal_buy_commodity = Commodity.create!(name: "Terminal Buys This", is_sellable: true)
    @terminal_sell_commodity = Commodity.create!(name: "Terminal Sells This", is_sellable: false)

    ProductionFacility.create!(
      facility_name: "Test Producer",
      location_name: @location.name,
      commodity_name: @terminal_buy_commodity.name,
      production_rate: 5,
      consumption_rate: 0,
      inventory: 1000,
      max_inventory: 2000,
      local_buy_price: 9.62,
      local_sell_price: nil,
      price_buy: 12.0,
      price_sell: 0.0,
      scu_buy: 10,
      status_buy: 7,
      status_sell: 0
    )
    ProductionFacility.create!(
      facility_name: "Test TDD",
      location_name: @location.name,
      commodity_name: @terminal_sell_commodity.name,
      terminal_name: "Test TDD",
      production_rate: 0,
      consumption_rate: 5,
      inventory: 0,
      max_inventory: 20,
      local_buy_price: nil,
      local_sell_price: 384.56,
      price_buy: 0.0,
      price_sell: 326.0,
      scu_buy: 0,
      scu_sell_stock: 0,
      status_buy: 0,
      status_sell: 1
    )
  end

  test "available and sellable commodity lists use opposite terminal trade directions" do
    buy_names = TradeService
      .list_available_commodities(username: @user.username)
      .dig(:message, :commodities)
      .map { |commodity| commodity[:commodity_name] }
    sell_names = TradeService
      .list_sellable_commodities(username: @user.username, shard: @shard.name)
      .dig(:message, :commodities)
      .map { |commodity| commodity[:commodity_name] }

    assert_includes buy_names, "Terminal Buys This"
    refute_includes buy_names, "Terminal Sells This"
    assert_includes sell_names, "Terminal Sells This"
    refute_includes sell_names, "Terminal Buys This"
    assert_empty buy_names & sell_names
    refute @terminal_sell_commodity.is_sellable
  end

  test "sellable list comes from terminal sell-side fields without requiring stock or cargo" do
    commodities = TradeService
      .list_sellable_commodities(username: @user.username, shard: @shard.name)
      .dig(:message, :commodities)
    commodity = commodities.find { |item| item[:commodity_name] == "Terminal Sells This" }

    refute_nil commodity
    assert_equal 384.56, commodity[:sell_price].to_f
    assert_equal 0, commodity[:scu]
  end

  test "loading ticks preserve existing cargo loading balance" do
    assert_equal 50, TradeService.loading_ticks_for_scu(20)
  end

  test "loading time converts loading ticks to real seconds" do
    assert_equal 250, TradeService.loading_time_seconds_for_scu(20)

    Setting.find_by!(key: "seconds_per_tick").update!(value: "2")

    assert_equal 100, TradeService.loading_time_seconds_for_scu(20)
  end

  test "buy returns loading_time as real seconds" do
    result = TradeService.buy(
      username: @user.username,
      wallet_balance: @shard_user.wallet_balance,
      commodity_name: @terminal_buy_commodity.name,
      scu: 2,
      shard: @shard.name,
      ship_guid: @user_ship.guid,
      ship_slug: @ship.slug
    )

    assert_equal "success", result[:status]
    assert_equal 14, result[:loading_ticks]
    assert_equal 70, result[:loading_time]
    assert_kind_of Numeric, result[:loading_time]
  end
end
