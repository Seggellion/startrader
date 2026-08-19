require "test_helper"
require_relative "../support/fake_rabbitmq"

class RabbitmqSenderTest < ActiveSupport::TestCase
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
    RabbitmqConnection.reset!

    Setting.create!(key: "secret_guid", value: "test-secret-guid", setting_type: "text")

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-channel-uuid")
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 4, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
  end

  teardown do
    RabbitmqConnection.reset!
  end

  test "ship report publishes to the environment recorded on the travel" do
    travel = create_travel(rabbitmq_environment: "dev")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      RabbitmqSender.send_ship_report(travel)
    end

    assert_equal ["dev"], recorder.requested_environments
    assert_equal 1, recorder.publications_for("dev").size
    assert_empty recorder.publications_for("prod")
  end

  test "ship report publishes to production for a production travel" do
    travel = create_travel(rabbitmq_environment: "prod")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      RabbitmqSender.send_ship_report(travel)
    end

    assert_equal ["prod"], recorder.requested_environments
    assert_equal 1, recorder.publications_for("prod").size
    assert_empty recorder.publications_for("dev")
  end

  test "travels bound to different environments never cross route" do
    prod_travel = create_travel(rabbitmq_environment: "prod", travel_guid: "prod-travel", ship_guid: "prod-ship")
    dev_travel = create_travel(rabbitmq_environment: "dev", travel_guid: "dev-travel", ship_guid: "dev-ship")
    second_prod_travel = create_travel(rabbitmq_environment: "prod", travel_guid: "prod-travel-2", ship_guid: "prod-ship-2")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      [prod_travel, dev_travel, second_prod_travel].each { |travel| RabbitmqSender.send_ship_report(travel) }
    end

    assert_equal %w[prod dev prod], recorder.requested_environments

    prod_guids = recorder.publications_for("prod").map { |publication| publication[:message].split("|").last }
    dev_guids = recorder.publications_for("dev").map { |publication| publication[:message].split("|").last }

    assert_equal %w[prod-travel prod-travel-2], prod_guids
    assert_equal %w[dev-travel], dev_guids
  end

  test "message protocol is unchanged regardless of environment" do
    travel = create_travel(rabbitmq_environment: "dev")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      RabbitmqSender.send_ship_report(travel)
    end

    publication = recorder.publications_for("dev").first
    user_ship = travel.user_ship

    assert_equal "MaidenB0T_events", publication[:exchange]
    assert_equal({ durable: true }, publication[:exchange_options])
    assert_equal "maidenb0tevents.testshard", publication[:routing_key]
    assert_equal({ tagId: "maidenb0tevents.testshard" }, publication[:headers])
    assert_equal true, publication[:persistent]
    assert_equal [
      "testshard",
      "ShipArrival",
      user_ship.user.uid,
      travel.departure_tick,
      travel.arrival_tick,
      @shard.channel_uuid,
      user_ship.user.username,
      user_ship.guid,
      user_ship.status,
      @ship.model,
      "test-secret-guid",
      @from_location.name,
      @to_location.name,
      travel.travel_guid
    ].join("|"), publication[:message]
  end

  test "ship report logs the environment without leaking the secret guid" do
    travel = create_travel(rabbitmq_environment: "dev")
    recorder = FakeRabbitmq::ChannelRecorder.new

    logged = capture_rails_log do
      RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
        RabbitmqSender.send_ship_report(travel)
      end
    end

    assert_includes logged, "rabbitmq environment dev"
    refute_includes logged, "test-secret-guid"
    assert_includes logged, "[REDACTED]"
  end

  test "a travel with a blank environment still publishes to production" do
    travel = create_travel(rabbitmq_environment: "prod")
    travel.update_column(:rabbitmq_environment, "")
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      RabbitmqSender.send_ship_report(travel.reload)
    end

    assert_equal ["prod"], recorder.requested_environments
  end

  test "an unavailable development broker raises instead of publishing to production" do
    travel = create_travel(rabbitmq_environment: "dev")
    Setting.create!(key: "rabbitmq_host", value: "prod-host", setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_host", value: "dev-host", setting_type: "text")

    FakeRabbitmq.stub_bunny(unreachable: ["dev-host"]) do
      assert_raises(RabbitmqConnection::UnavailableError) { RabbitmqSender.send_ship_report(travel) }

      prod_channel = RabbitmqConnection.channel_for("prod")
      assert_empty prod_channel.publications
    end
  end

  test "streamer events always publish to production" do
    recorder = FakeRabbitmq::ChannelRecorder.new

    RabbitmqConnection.stub(:channel_for, recorder.to_proc) do
      RabbitmqSender.send_event("Seggellion")
    end

    assert_equal ["prod"], recorder.requested_environments
    publication = recorder.publications_for("prod").first
    assert_equal "maidenb0tevents.seggellion", publication[:routing_key]
    assert_equal "Seggellion|CheckStatus", publication[:message]
    assert_empty recorder.publications_for("dev")
  end

  private

  def create_travel(rabbitmq_environment:, travel_guid: "travel-guid", ship_guid: "ship-guid")
    user = User.create!(
      username: "Pilot#{SecureRandom.hex(3)}",
      twitch_id: "twitch-#{SecureRandom.hex(3)}",
      uid: "uid-#{SecureRandom.hex(3)}",
      user_type: "player"
    )
    shard_user = ShardUser.create!(user: user, shard: @shard, shard_name: @shard.name)
    user_ship = UserShip.create!(
      user: user,
      ship: @ship,
      shard: @shard,
      shard_user: shard_user,
      shard_name: @shard.name,
      guid: ship_guid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0,
      status: "in_transit"
    )

    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: travel_guid,
      departure_tick: 10,
      arrival_tick: 20,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      rabbitmq_environment: rabbitmq_environment
    )
  end

  def capture_rails_log
    buffer = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(buffer)
    yield
    buffer.string
  ensure
    Rails.logger = original_logger
  end
end
