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
      .list_available_commodities(username: @user.username, shard: @shard.name)
      .fetch(:commodities)
      .map { |commodity| commodity[:commodity_name] }
    sell_names = TradeService
      .list_sellable_commodities(username: @user.username, shard: @shard.name)
      .fetch(:commodities)
      .map { |commodity| commodity[:commodity_name] }

    assert_includes buy_names, "Terminal Buys This"
    refute_includes buy_names, "Terminal Sells This"
    assert_includes sell_names, "Terminal Sells This"
    refute_includes sell_names, "Terminal Buys This"
    assert_empty buy_names & sell_names
    refute @terminal_sell_commodity.is_sellable
  end

  test "status finds ship by guid and broadcaster channel uuid" do
    response = TradeService.status(
      ship_guid: @user_ship.guid,
      broadcaster_id: @shard.channel_uuid,
      wallet_balance: 40_000
    )

    assert_equal "success", response[:status]
    assert_equal 40_000, response[:wallet_balance]
    assert_equal @ship.model, response[:ship][:model]
    assert_equal @location.name, response[:ship][:location]
    assert_equal [], response[:cargo]
    assert_equal 40_000, @shard_user.reload.wallet_balance
  end

  test "status preserves success response shape" do
    response = TradeService.status(
      ship_guid: @user_ship.guid,
      broadcaster_id: @shard.channel_uuid
    )

    assert_equal [:cargo, :ship, :status, :wallet_balance], response.keys.sort
    assert_equal(
      [
        :arrival_tick,
        :available_cargo_space,
        :current_tick,
        :from_location,
        :location,
        :model,
        :time_remaining,
        :to_location,
        :total_scu,
        :travel_status,
        :used_scu
      ],
      response[:ship].keys.sort
    )
  end

  test "status defaults zero wallet balance to 15000" do
    @shard_user.update!(wallet_balance: 0)

    response = TradeService.status(ship_guid: @user_ship.guid, broadcaster_id: @shard.channel_uuid)

    assert_equal 15_000, response[:wallet_balance]
    assert_equal 15_000, @shard_user.reload.wallet_balance
  end

  test "status requires ship guid" do
    error = assert_raises(TradeService::ValidationError) do
      TradeService.status(broadcaster_id: @shard.channel_uuid)
    end

    assert_equal "ship_guid is required", error.message
  end

  test "status requires broadcaster id" do
    error = assert_raises(TradeService::ValidationError) do
      TradeService.status(ship_guid: @user_ship.guid)
    end

    assert_equal "broadcaster_id is required", error.message
  end

  test "status rejects unknown broadcaster" do
    error = assert_raises(ActiveRecord::RecordNotFound) do
      TradeService.status(ship_guid: @user_ship.guid, broadcaster_id: "unknown")
    end

    assert_equal "Shard not found", error.message
  end

  test "status rejects unknown ship" do
    error = assert_raises(ActiveRecord::RecordNotFound) do
      TradeService.status(ship_guid: "unknown", broadcaster_id: @shard.channel_uuid)
    end

    assert_equal "Ship not found", error.message
  end

  test "status rejects ship from a different broadcaster" do
    other_shard = Shard.create!(name: "OtherShard", region: "us", channel_uuid: "other-shard-guid")

    error = assert_raises(TradeService::ValidationError) do
      TradeService.status(ship_guid: @user_ship.guid, broadcaster_id: other_shard.channel_uuid)
    end

    assert_equal "Ship does not belong to this broadcaster", error.message
  end

  test "status rejects non numeric wallet balance" do
    error = assert_raises(TradeService::ValidationError) do
      TradeService.status(
        ship_guid: @user_ship.guid,
        broadcaster_id: @shard.channel_uuid,
        wallet_balance: "not-money"
      )
    end

    assert_equal "wallet_balance must be numeric", error.message
  end

  test "available commodity list keeps message human-readable and data top-level" do
    response = TradeService.list_available_commodities(username: @user.username, shard: @shard.name)

    assert_equal "success", response[:status]
    assert_kind_of String, response[:message]
    assert_equal @location.name, response[:location]
    assert_kind_of Array, response[:commodities]
    refute_kind_of Hash, response[:message]
  end

  test "sellable commodity list keeps message human-readable and data top-level" do
    response = TradeService.list_sellable_commodities(username: @user.username, shard: @shard.name)

    assert_equal "success", response[:status]
    assert_kind_of String, response[:message]
    assert_equal @location.name, response[:location]
    assert_kind_of Array, response[:commodities]
    refute_kind_of Hash, response[:message]
  end

  test "available commodity empty list keeps data top-level" do
    ProductionFacility.delete_all

    response = TradeService.list_available_commodities(username: @user.username, shard: @shard.name)

    assert_equal "error", response[:status]
    assert_kind_of String, response[:message]
    assert_equal @location.name, response[:location]
    assert_equal [], response[:commodities]
    refute_kind_of Hash, response[:message]
  end

  test "sellable commodity empty list keeps data top-level" do
    ProductionFacility.delete_all

    response = TradeService.list_sellable_commodities(username: @user.username, shard: @shard.name)

    assert_equal "error", response[:status]
    assert_kind_of String, response[:message]
    assert_equal @location.name, response[:location]
    assert_equal [], response[:commodities]
    refute_kind_of Hash, response[:message]
  end

  test "sellable list comes from terminal sell-side fields without requiring stock or cargo" do
    commodities = TradeService
      .list_sellable_commodities(username: @user.username, shard: @shard.name)
      .fetch(:commodities)
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

  test "listed commodity at child trade location can be bought from same ship" do
    crusader = Location.create!(
      name: "Crusader",
      classification: "planet",
      star_system_name: "Stanton"
    )
    orison = Location.create!(
      name: "Orison",
      classification: "city",
      star_system_name: "Stanton",
      parent_name: crusader.name,
      planet_name: crusader.name
    )
    waste = Commodity.create!(name: "Waste", is_sellable: true)
    waste_facility = ProductionFacility.create!(
      facility_name: "Orison Commodity Terminal",
      location_name: orison.name,
      commodity_name: waste.name,
      production_rate: 5,
      consumption_rate: 0,
      inventory: 100,
      max_inventory: 200,
      local_buy_price: 9.62,
      local_sell_price: nil,
      price_buy: 12.0,
      price_sell: 0.0,
      scu_buy: 10,
      status_buy: 7,
      status_sell: 0
    )
    @user_ship.update!(location_name: crusader.name, total_scu: 10, used_scu: 0)

    listed = TradeService.list_available_commodities(
      username: @user.username,
      shard: @shard.name,
      ship_guid: @user_ship.guid,
      ship_slug: @ship.slug
    )

    assert_equal "success", listed[:status]
    assert_equal orison.name, listed[:location]
    assert_includes listed[:commodities].map { |commodity| commodity[:commodity_name] }, waste.name

    result = TradeService.buy(
      username: @user.username,
      wallet_balance: @shard_user.wallet_balance,
      commodity_name: "waste",
      scu: "5",
      shard: @shard.name,
      ship_guid: @user_ship.guid,
      ship_slug: @ship.slug
    )

    assert_equal "success", result[:status]
    assert_includes result[:message], "at Orison"
    assert_equal 5, result[:scu]
    assert_equal 48.1, result[:total_capital]
    assert_equal 95, waste_facility.reload.inventory
    assert_equal 1, UserShipCargo.where(user_ship: @user_ship, commodity: waste, scu: 5).count
  end

  test "buy error uses child trade location when parent has no matching commodity facility" do
    crusader = Location.create!(
      name: "Crusader",
      classification: "planet",
      star_system_name: "Stanton"
    )
    orison = Location.create!(
      name: "Orison",
      classification: "city",
      star_system_name: "Stanton",
      parent_name: crusader.name,
      planet_name: crusader.name
    )
    waste = Commodity.create!(name: "Waste", is_sellable: true)
    agricium = Commodity.create!(name: "Agricium", is_sellable: true)
    ProductionFacility.create!(
      facility_name: "Orison Commodity Terminal",
      location_name: orison.name,
      commodity_name: waste.name,
      production_rate: 5,
      consumption_rate: 0,
      inventory: 100,
      max_inventory: 200,
      local_buy_price: 9.62,
      local_sell_price: nil,
      price_buy: 12.0,
      price_sell: 0.0,
      scu_buy: 10,
      status_buy: 7,
      status_sell: 0
    )
    @user_ship.update!(location_name: crusader.name, total_scu: 10, used_scu: 0)

    error = assert_raises(TradeService::InsufficientInventoryError) do
      TradeService.buy(
        username: @user.username,
        wallet_balance: @shard_user.wallet_balance,
        commodity_name: agricium.name,
        scu: "5",
        shard: @shard.name,
        ship_guid: @user_ship.guid,
        ship_slug: @ship.slug
      )
    end

    assert_equal "No matching facility found for Orison and Agricium.", error.message
  end
end
