require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all

    @commodity = Commodity.create!(name: "Agricium", is_sellable: true)
  end

  test "destroying user destroys associated star bitizen runs" do
    user = create_user!("destroy-user")
    first_run = create_star_bitizen_run!(user: user)
    second_run = create_star_bitizen_run!(user: user)

    assert_difference("User.count", -1) do
      assert_difference("StarBitizenRun.count", -2) do
        user.destroy!
      end
    end

    refute User.exists?(user.id)
    refute StarBitizenRun.exists?(first_run.id)
    refute StarBitizenRun.exists?(second_run.id)
  end

  test "deleting user cascades associated star bitizen runs at the database level" do
    user = create_user!("delete-user")
    run = create_star_bitizen_run!(user: user)

    assert_difference("User.count", -1) do
      assert_difference("StarBitizenRun.count", -1) do
        user.delete
      end
    end

    refute User.exists?(user.id)
    refute StarBitizenRun.exists?(run.id)
  end

  private

  def create_user!(identifier)
    User.create!(
      username: identifier,
      twitch_id: "#{identifier}-twitch",
      uid: "#{identifier}-guid",
      user_type: "player"
    )
  end

  def create_star_bitizen_run!(user:)
    StarBitizenRun.create!(
      user: user,
      commodity: @commodity,
      commodity_name: @commodity.name,
      profit: 0,
      scu: 4
    )
  end
end
