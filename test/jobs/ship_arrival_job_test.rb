require "test_helper"

class ShipArrivalJobTest < ActiveJob::TestCase
  setup do
    ShipTravel.delete_all
    UserShip.delete_all
    User.delete_all
    Ship.delete_all
    Location.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      guid: "ship-guid",
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "in_transit"
    )

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 105, sequence: 1)
    end
  end

  test "processes skipped arrivals using arrival tick less than current tick" do
    travel = create_travel(arrival_tick: 100)
    sent_reports = 0

    RabbitmqSender.stub(:send_ship_report, ->(_travel) { sent_reports += 1 }) do
      ShipArrivalJob.perform_now
    end

    assert_equal 105, travel.reload.completed_at_tick
    assert_equal @to_location.name, @user_ship.reload.location_name
    assert_equal "landed", @user_ship.status
    assert_equal 1, sent_reports
  end

  test "does not process paused travel" do
    travel = create_travel(arrival_tick: 100, is_paused: true)

    RabbitmqSender.stub(:send_ship_report, ->(_travel) { raise "paused travel should not arrive" }) do
      ShipArrivalJob.perform_now
    end

    assert_nil travel.reload.completed_at_tick
    assert_equal "in_transit", @user_ship.reload.status
  end

  private

  def create_travel(arrival_tick:, is_paused: false)
    ShipTravel.create!(
      user_ship: @user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: arrival_tick,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      is_paused: is_paused
    )
  end
end
