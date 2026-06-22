require "test_helper"

class UserShipCargoTest < ActiveSupport::TestCase
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all

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
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "ship-guid",
      ship_slug: @ship.slug,
      total_scu: @ship.scu,
      used_scu: 0
    )
    @commodity = Commodity.create!(name: "Agricium", is_sellable: true)
    @other_commodity = Commodity.create!(name: "Laranite", is_sellable: true)
  end

  test "creating cargo updates ship used_scu" do
    UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)

    assert_equal 4, @user_ship.reload.used_scu
  end

  test "updating cargo scu updates ship used_scu" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)

    cargo.update!(scu: 7)

    assert_equal 7, @user_ship.reload.used_scu
  end

  test "destroying one cargo updates ship used_scu" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)
    UserShipCargo.create!(user_ship: @user_ship, commodity: @other_commodity, scu: 3)

    cargo.destroy!

    assert_equal 3, @user_ship.reload.used_scu
  end

  test "destroying final cargo resets ship used_scu" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)

    cargo.destroy!

    assert_equal 0, @user_ship.reload.used_scu
  end

  test "destroying cargo still nullifies related star bitizen runs" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)
    run = StarBitizenRun.create!(
      user: @user,
      user_ship: @user_ship,
      user_ship_cargo: cargo,
      commodity: @commodity,
      commodity_name: @commodity.name,
      profit: 0,
      scu: 4
    )

    cargo.destroy!

    assert_nil run.reload.user_ship_cargo_id
  end

  test "used_scu is recalculated from cargo sum instead of drifted value" do
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)
    UserShipCargo.create!(user_ship: @user_ship, commodity: @other_commodity, scu: 3)
    @user_ship.update!(used_scu: 99)

    cargo.update!(scu: 5)

    assert_equal 8, @user_ship.reload.used_scu
  end

  test "moving cargo between ships recalculates both ships" do
    other_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      guid: "other-ship-guid",
      ship_slug: @ship.slug,
      total_scu: @ship.scu,
      used_scu: 0
    )
    cargo = UserShipCargo.create!(user_ship: @user_ship, commodity: @commodity, scu: 4)

    cargo.update!(user_ship: other_ship)

    assert_equal 0, @user_ship.reload.used_scu
    assert_equal 4, other_ship.reload.used_scu
  end
end
