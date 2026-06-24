require "test_helper"

class TickTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")
    Setting.delete_all
  end

  test "seconds_per_tick reads settings dynamically" do
    Setting.create!(key: "seconds_per_tick", value: "5", setting_type: "text")

    assert_equal 5, Tick.seconds_per_tick

    Setting.find_by!(key: "seconds_per_tick").update!(value: "2")

    assert_equal 2, Tick.seconds_per_tick
  end

  test "seconds_per_tick falls back safely for missing blank zero and invalid settings" do
    assert_equal 1, Tick.seconds_per_tick

    Setting.create!(key: "seconds_per_tick", value: "", setting_type: "text")
    assert_equal 1, Tick.seconds_per_tick

    Setting.find_by!(key: "seconds_per_tick").update!(value: "0")
    assert_equal 1, Tick.seconds_per_tick

    Setting.find_by!(key: "seconds_per_tick").update!(value: "not-a-number")
    assert_equal 1, Tick.seconds_per_tick
  end

  test "simulated seconds per tick is separate from real seconds per tick" do
    Setting.create!(key: "hours_per_tick", value: "2", setting_type: "text")

    assert_equal 7200, Tick.simulated_seconds_per_tick
    assert_equal 7200, Tick.hours_per_tick
  end

  test "increment broadcasts real seconds per tick" do
    Setting.create!(key: "seconds_per_tick", value: "5", setting_type: "text")
    broadcasts = []
    server = Object.new
    server.define_singleton_method(:broadcast) do |channel, payload|
      broadcasts << [channel, payload]
    end

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)

      ActionCable.stub(:server, server) do
        ShipArrivalJob.stub(:perform_now, nil) do
          ShipTravel.stub(:cleanup_stale_after_arrival!, nil) do
            Tick.increment!
          end
        end
      end
    end

    tick_broadcast = broadcasts.find { |channel, payload| channel == "tick" && payload[:type] == "tick" }

    refute_nil tick_broadcast
    assert_equal 11, tick_broadcast.last[:tick]
    assert_equal 5, tick_broadcast.last[:seconds_per_tick]
  end

  test "increment processes arrivals and stale cleanup after advancing the tick" do
    events = []
    server = Object.new
    server.define_singleton_method(:broadcast) { |_channel, _payload| }

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)

      ActionCable.stub(:server, server) do
        ShipArrivalJob.stub(:perform_now, -> { events << [:arrival, Tick.current] }) do
          ShipTravel.stub(:cleanup_stale_after_arrival!, ->(tick = Tick.current) { events << [:cleanup, tick] }) do
            Tick.increment!
          end
        end
      end
    end

    assert_equal [[:arrival, 11], [:cleanup, 11]], events
  end

  test "market price failures do not stop the tick increment" do
    server = Object.new
    server.define_singleton_method(:broadcast) { |_channel, _payload| }

    Tick.create!(current_tick: 10, sequence: 1)

    MarketPriceUpdater.stub(:update_prices!, -> { raise "market unavailable" }) do
      ActionCable.stub(:server, server) do
        ShipArrivalJob.stub(:perform_now, nil) do
          ShipTravel.stub(:cleanup_stale_after_arrival!, nil) do
            assert_nothing_raised { Tick.increment! }
          end
        end
      end
    end

    assert_equal 11, Tick.current
  end

  test "non-critical after-tick side effect failures do not stop the tick increment" do
    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end

    ActionCable.stub(:server, Object.new.tap { |server| server.define_singleton_method(:broadcast) { |_channel, _payload| } }) do
      ShipArrivalJob.stub(:perform_now, -> { raise "arrival unavailable" }) do
        ShipTravel.stub(:cleanup_stale_after_arrival!, nil) do
          assert_nothing_raised { Tick.increment! }
        end
      end
    end

    assert_equal 11, Tick.current
  end
end
