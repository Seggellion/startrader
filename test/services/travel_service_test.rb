require "test_helper"

class TravelServiceTest < ActiveSupport::TestCase
  # These tests exercise identity/lifecycle/broker policy. Physical geometry
  # has its own real request/service fixtures in OrbitalIntegrationTest.
  def run
    calculator = Struct.new(:calculate).new(2)
    TravelTimeCalculator.stub(:new, calculator) { super }
  end

  setup do
    StarBitizenRun.delete_all
    ShipTravel.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Setting.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    Setting.create!(key: "interdiction_window_percent", value: "50", setting_type: "text")
    Setting.create!(key: "seconds_per_tick", value: "30", setting_type: "text")
    Setting.create!(key: "hours_per_tick", value: "1", setting_type: "text")

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end

    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
  end

  test "defaults to production when no environment is supplied" do
    travel = build_travel(travel_guid: "default-env-travel")

    assert_equal "prod", travel.rabbitmq_environment
    assert_equal "prod", travel.reload.rabbitmq_environment
  end

  test "persists an explicit development environment on the travel" do
    travel = build_travel(travel_guid: "dev-env-travel", rabbitmq_environment: "dev")

    assert_equal "dev", travel.rabbitmq_environment
    assert_equal "dev", ShipTravel.find_by!(travel_guid: "dev-env-travel").rabbitmq_environment
  end

  test "persists an explicit production environment on the travel" do
    travel = build_travel(travel_guid: "prod-env-travel", rabbitmq_environment: "prod")

    assert_equal "prod", ShipTravel.find_by!(travel_guid: "prod-env-travel").rabbitmq_environment
  end

  test "normalizes case and whitespace before persisting" do
    travel = build_travel(travel_guid: "messy-env-travel", rabbitmq_environment: "  DEV \n")

    assert_equal "dev", travel.reload.rabbitmq_environment
  end

  test "blank environments fall back to production" do
    travel = build_travel(travel_guid: "blank-env-travel", rabbitmq_environment: "   ")

    assert_equal "prod", travel.reload.rabbitmq_environment
  end

  test "rejects an unsupported environment without creating a travel" do
    assert_raises(RabbitmqConnection::UnknownEnvironmentError) do
      TravelService.new(
        user_ship: create_user_ship,
        to_location: @to_location,
        travel_guid: "staging-env-travel",
        rabbitmq_environment: "staging"
      )
    end

    assert_nil ShipTravel.find_by(travel_guid: "staging-env-travel")
  end

  private

  def build_travel(travel_guid:, rabbitmq_environment: nil, user_ship: create_user_ship)
    TravelService.new(
      user_ship: user_ship,
      to_location: @to_location,
      travel_guid: travel_guid,
      start_tick: Tick.current,
      rabbitmq_environment: rabbitmq_environment
    ).call
  end

  def create_user_ship
    UserShip.create!(
      user: @user,
      ship: @ship,
      guid: "ship-#{SecureRandom.hex(4)}",
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "docked"
    )
  end
end
