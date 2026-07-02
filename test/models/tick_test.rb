require "test_helper"

class TickTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")
    Setting.delete_all
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Ship.delete_all
    Location.delete_all
    ProductionFacility.delete_all
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

  test "one tick removes old unpaused ship travels" do
    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 104, sequence: 1)
    end

    old_travel = create_travel(arrival_tick: 10)
    completed_old_travel = create_travel(arrival_tick: 20, completed_at_tick: 20)
    paused_travel = create_travel(arrival_tick: 0, is_paused: true)
    future_travel = create_travel(arrival_tick: 106)

    server = Object.new
    server.define_singleton_method(:broadcast) { |_channel, _payload| }

    RabbitmqSender.stub(:send_ship_report, nil) do
      MarketPriceUpdater.stub(:update_prices!, nil) do
        ActionCable.stub(:server, server) do
          Tick.increment!
        end
      end
    end

    refute ShipTravel.exists?(old_travel.id)
    refute ShipTravel.exists?(completed_old_travel.id)
    assert ShipTravel.exists?(paused_travel.id)
    assert ShipTravel.exists?(future_travel.id)
  end

  test "status correction preserves paused ships and corrects ships without valid travel" do
    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 105, sequence: 1)
    end

    active_ship = create_user_ship(status: "in_transit")
    create_travel(user_ship: active_ship, arrival_tick: 110)

    paused_ship = create_user_ship(status: "in_transit")
    create_travel(user_ship: paused_ship, arrival_tick: 0, is_paused: true)

    stranded_ship = create_user_ship(status: "in_transit")

    expired_ship = create_user_ship(status: "in_transit")
    create_travel(user_ship: expired_ship, arrival_tick: 100)

    Tick.instance.send(:correct_ship_statuses)

    assert_equal "in_transit", active_ship.reload.status
    assert_equal "in_transit", paused_ship.reload.status
    assert_equal "aimlessly floating in space", stranded_ship.reload.status
    assert_equal "aimlessly floating in space", expired_ship.reload.status
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

  test "increment suppresses per row market broadcasts during tick facility updates" do
    old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    facilities = 3.times.map do |index|
      create_market_facility(facility_name: "Tick Facility #{index}", inventory: index)
    end

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end

    updater = ->(broadcast: false) do
      assert_equal false, broadcast
      facilities.each { |facility| facility.update!(inventory: facility.inventory + 1) }
    end
    server = Object.new
    server.define_singleton_method(:broadcast) { |_channel, _payload| }

    assert_no_enqueued_jobs only: Turbo::Streams::ActionBroadcastJob do
      MarketPriceUpdater.stub(:update_prices!, updater) do
        ActionCable.stub(:server, server) do
          ShipArrivalJob.stub(:perform_now, nil) do
            ShipTravel.stub(:cleanup_stale_after_arrival!, nil) do
              Tick.increment!
            end
          end
        end
      end
    end
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
    ProductionFacility.suppress_market_broadcasts = false
    ActiveJob::Base.queue_adapter = old_queue_adapter if old_queue_adapter
  end

  private

  def create_market_facility(overrides = {})
    ProductionFacility.create!({
      facility_name: "Tick Facility",
      production_rate: 0,
      consumption_rate: 0,
      inventory: 0,
      max_inventory: 100,
      local_buy_price: 80,
      local_sell_price: 100,
      price_buy: 80,
      price_sell: 100,
      scu_buy: 10,
      scu_sell: 10,
      scu_sell_stock: 50,
      status_buy: 1,
      status_sell: 1,
      commodity_name: "Agricium",
      terminal_name: "Lorville CBD",
      location_name: "Lorville"
    }.merge(overrides))
  end

  def create_user_ship(status: "docked")
    user = User.create!(
      username: "TickPilot-#{SecureRandom.hex(4)}",
      twitch_id: "tick-twitch-#{SecureRandom.hex(4)}",
      uid: "tick-guid-#{SecureRandom.hex(4)}",
      user_type: "player"
    )
    ship = Ship.create!(model: "Drake Cutter #{SecureRandom.hex(4)}", slug: "drake-cutter-#{SecureRandom.hex(4)}", scu: 4, speed: 100)
    location = Location.create!(name: "Orison #{SecureRandom.hex(4)}", classification: "city", star_system_name: "Stanton")

    UserShip.create!(
      user: user,
      ship: ship,
      guid: SecureRandom.uuid,
      ship_slug: ship.slug,
      location: location,
      total_scu: ship.scu,
      used_scu: 0,
      status: status
    )
  end

  def create_travel(user_ship: create_user_ship, arrival_tick:, is_paused: false, completed_at_tick: nil)
    from_location = user_ship.location || Location.create!(name: "From #{SecureRandom.hex(4)}", classification: "city", star_system_name: "Stanton")
    to_location = Location.create!(name: "Area18 #{SecureRandom.hex(4)}", classification: "city", star_system_name: "Stanton")

    ShipTravel.create!(
      user_ship: user_ship,
      from_location: from_location,
      to_location: to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 1,
      arrival_tick: arrival_tick,
      total_duration_ticks: 10,
      interdict_window_percent: 50,
      is_paused: is_paused,
      completed_at_tick: completed_at_tick
    )
  end
end
