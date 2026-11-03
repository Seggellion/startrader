require 'test_helper'
require_relative '../support/travel_repair_fixtures'

class StatusLocationSyncConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  include TravelRepairFixtures
  setup { setup_travel_repair }
  teardown { cleanup_travel_repair }

  def race(*actions)
    ready = Queue.new
    start = Queue.new
    threads = actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout='4s'")
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          action.call
        ensure
          connection.execute('RESET lock_timeout')
        end
      end
    end
    pids = threads.map { ready.pop }
    assert_equal pids.size, pids.uniq.size
    threads.size.times { start << true }
    threads.map do |thread|
      assert thread.join(10), 'Concurrent status operation did not finish'
      thread.value
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  def report(ship_guid: @hull.guid)
    TradeService.status(ship_guid: ship_guid, ship_model: @catalog_ship.model, shard_uuid: @shard.channel_uuid,
      player_guid: @user.uid, player_name: @user.username, location: @origin.name)
  end

  test 'status racing arrival cannot restore stale origin after completion' do
    travel = gate_start
    race(-> { report },
      -> { ShipTravelArrivalProcessor.new(travel: ShipTravel.find(travel.id), current_tick: 108).call })
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal @destination.name, @player.reload.current_location_name
    assert_equal 'completed', TravelRequestReceipt.sole.outcome
    assert_equal 1, TravelArrivalEvent.count
    assert_empty ShipTravel.all
  end

  test 'status racing pause cannot relocate or lose paused journey' do
    travel = gate_start
    race(-> { report }, -> { ShipTravel.find(travel.id).interdict!(100) })
    assert travel.reload.is_paused?
    assert_equal 0, travel.arrival_tick
    assert_equal 8, travel.remaining_ticks_from_arrival
    assert_equal @gate.name, @hull.reload.location_name
    assert_equal @gate.name, @player.reload.current_location_name
    assert_equal 'interdicted', @hull.status
    assert_empty TravelArrivalEvent.all
  end

  test 'status on a different ship serializes shared player against arrival' do
    other = UserShip.create!(user: @user, ship: @catalog_ship, shard: @shard, shard_user: @player,
      guid: 'other-status-ship', location_name: @origin.name, total_scu: 20, used_scu: 0)
    travel = gate_start
    race(-> { report(ship_guid: other.guid) },
      -> { ShipTravelArrivalProcessor.new(travel: ShipTravel.find(travel.id), current_tick: 108).call })
    assert_equal @destination.name, @player.reload.current_location_name
    assert_equal @destination.name, @hull.reload.location_name
    assert_equal @origin.name, other.reload.location_name
  ensure
    other&.destroy!
  end

  test 'simultaneous initial status for one GUID retries without duplicate ships' do
    race(-> { report(ship_guid: 'simultaneous-status-new') },
      -> { report(ship_guid: 'simultaneous-status-new') })
    assert_equal 1, UserShip.where(guid: 'simultaneous-status-new').count
  ensure
    UserShip.where(guid: 'simultaneous-status-new').destroy_all
  end
end
