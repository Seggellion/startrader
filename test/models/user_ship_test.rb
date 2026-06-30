require "test_helper"

class UserShipTest < ActiveSupport::TestCase
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all

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
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 12, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
    @commodity = Commodity.create!(name: "Agricium", is_sellable: true)
  end

  test "destroying user ship destroys associated cargo records" do
    user_ship = create_user_ship
    cargo = UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 4)

    assert_difference("UserShipCargo.count", -1) do
      user_ship.destroy!
    end

    refute UserShipCargo.exists?(cargo.id)
  end

  test "destroying user ship does not leave orphaned cargo rows" do
    user_ship = create_user_ship
    UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 4)
    UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 3)
    user_ship_id = user_ship.id

    user_ship.destroy!

    assert_empty UserShipCargo.where(user_ship_id: user_ship_id)
  end

  test "destroying user ship still destroys associated ship travel records" do
    user_ship = create_user_ship
    travel = create_ship_travel(user_ship)

    assert_difference("ShipTravel.count", -1) do
      user_ship.destroy!
    end

    refute ShipTravel.exists?(travel.id)
  end

  test "destroying user ship nullifies star bitizen run cargo references" do
    user_ship = create_user_ship
    cargo = UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 4)
    run = StarBitizenRun.create!(
      user: @user,
      user_ship: user_ship,
      user_ship_cargo: cargo,
      commodity: @commodity,
      commodity_name: @commodity.name,
      profit: 0,
      scu: 4
    )

    user_ship.destroy!

    assert_nil run.reload.user_ship_cargo_id
  end

  test "destroying user ship with cargo does not raise during used scu recalculation" do
    user_ship = create_user_ship
    UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 4)

    assert_nothing_raised do
      user_ship.destroy!
    end
  end

  private

  def create_user_ship
    UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: SecureRandom.uuid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0
    )
  end

  def create_ship_travel(user_ship)
    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: 100,
      total_duration_ticks: 10,
      interdict_window_percent: 50
    )
  end
end
