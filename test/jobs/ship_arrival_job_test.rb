require "test_helper"
require_relative "../support/fake_rabbitmq"

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
    @shard = Shard.create!(name:'Arrival Test',region:'us',channel_uuid:'arrival-test')
    @shard_user = ShardUser.create!(user:@user,shard:@shard,shard_name:@shard.name)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
    @user_ship = UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      shard_name: @shard.name,
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

    refute ShipTravel.exists?(travel.id)
    assert_equal @to_location.name, @user_ship.reload.location_name
    assert_equal "landed", @user_ship.status
    assert_equal 1, sent_reports
  end

  test "arrival processing is idempotent after destroying travel" do
    travel = create_travel(arrival_tick: 100)
    sent_reports = 0

    RabbitmqSender.stub(:send_ship_report, ->(_travel) { sent_reports += 1 }) do
      ShipArrivalJob.perform_now
      ShipArrivalJob.perform_now
    end

    refute ShipTravel.exists?(travel.id)
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

  test "delayed arrival publishes to the environment recorded when the travel began" do
    create_travel(arrival_tick: 100, rabbitmq_environment: "dev")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      ShipArrivalJob.perform_now
    end

    assert_equal ["dev"], recorder.requested_environments
    assert_equal 1, recorder.publications_for("dev").size
    assert_empty recorder.publications_for("prod")
  end

  test "delayed arrival for a production travel publishes to production" do
    create_travel(arrival_tick: 100, rabbitmq_environment: "prod")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      ShipArrivalJob.perform_now
    end

    assert_equal ["prod"], recorder.requested_environments
    assert_empty recorder.publications_for("dev")
  end

  test "travels bound to different environments arriving together do not cross route" do
    dev_travel = create_travel(arrival_tick: 100, rabbitmq_environment: "dev")
    prod_travel = create_travel(arrival_tick: 101, rabbitmq_environment: "prod", user_ship: create_user_ship(guid: "second-ship-guid"))
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      ShipArrivalJob.perform_now
    end

    assert_equal %w[dev prod], recorder.requested_environments.sort
    assert_equal [dev_travel.travel_guid], recorder.publications_for("dev").map { |p| p[:message].split("|").last }
    assert_equal [prod_travel.travel_guid], recorder.publications_for("prod").map { |p| p[:message].split("|").last }
  end

  test "an unavailable development broker leaves the travel unprocessed instead of publishing to production" do
    travel = create_travel(arrival_tick: 100, rabbitmq_environment: "dev")
    Setting.create!(key: "rabbitmq_host", value: "prod-host", setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_host", value: "dev-host", setting_type: "text")
    RabbitmqConnection.reset!

    FakeRabbitmq.stub_bunny(unreachable: ["dev-host"]) do
      assert_raises(RabbitmqConnection::UnavailableError) { ShipArrivalJob.perform_now }

      assert_empty RabbitmqConnection.channel_for("prod").publications
    end

    assert ShipTravel.exists?(travel.id)
    assert_equal "in_transit", @user_ship.reload.status
  ensure
    RabbitmqConnection.reset!
  end

  test "an interdicted and resumed travel keeps its original environment" do
    travel = create_travel(arrival_tick: 100, rabbitmq_environment: "dev")
    travel.interdict!(95)
    travel.resume!(96)

    assert_equal "dev", travel.reload.rabbitmq_environment

    Tick.instance.update_columns(current_tick: travel.arrival_tick, sequence: travel.arrival_tick)
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      ShipArrivalJob.perform_now
    end

    assert_equal ["dev"], recorder.requested_environments
  end

  private

  def create_user_ship(guid:)
    UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: @shard_user,
      shard_name: @shard.name,
      guid: guid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "in_transit"
    )
  end

  def create_travel(arrival_tick:, is_paused: false, rabbitmq_environment: "prod", user_ship: nil)
    ShipTravel.create!(
      user_ship: user_ship || @user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: arrival_tick,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      is_paused: is_paused,
      rabbitmq_environment: rabbitmq_environment
    )
  end
end
