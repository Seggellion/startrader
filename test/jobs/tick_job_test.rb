require "test_helper"

class TickJobTest < ActiveSupport::TestCase
  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :delayed_job

    Delayed::Job.delete_all
    TickControl.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")
    Setting.delete_all

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end
  end

  teardown do
    Delayed::Job.delete_all
    TickControl.delete_all
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  test "schedules the next job when increment succeeds" do
    TickControl.instance.update!(running: true)

    without_tick_side_effects do
      TickJob.perform_now
    end

    assert_equal 11, Tick.current
    assert_equal 1, TickJob.future_count
  end

  test "still schedules the next job when increment raises" do
    control = TickControl.instance
    control.update!(running: true)

    Tick.stub(:increment!, -> { raise "tick exploded" }) do
      TickJob.perform_now
    end

    assert_equal 1, TickJob.future_count
    assert_equal 1, control.reload.failure_count
    assert_equal "RuntimeError", control.last_tick_error_class
  end

  test "does not increment or schedule when disabled" do
    TickControl.instance.update!(running: false)

    Tick.stub(:increment!, -> { raise "disabled tick should not run" }) do
      TickJob.perform_now
    end

    assert_equal 10, Tick.current
    assert_equal 0, TickJob.pending_count
  end

  test "ensure_scheduled does not enqueue duplicates" do
    TickControl.instance.update!(running: true)

    TickJob.ensure_scheduled!
    TickJob.ensure_scheduled!

    assert_equal 1, TickJob.pending_count
  end

  test "start schedules tick and watchdog jobs" do
    TickControl.instance.start!

    assert TickControl.instance.running?
    assert_equal 1, TickJob.pending_count
    assert_equal 1, TickWatchdogJob.pending_count
  end

  test "stop cancels queued jobs and future performs exit" do
    control = TickControl.instance
    control.start!

    control.stop!

    assert_equal 0, TickJob.pending_count
    assert_equal 0, TickWatchdogJob.pending_count

    Tick.stub(:increment!, -> { raise "stopped tick should not run" }) do
      TickJob.perform_now
    end

    assert_equal 10, Tick.current
  end

  test "failed delayed job rows do not count as a healthy pending tick" do
    TickControl.instance.update!(running: true)
    TickJob.perform_later
    TickJob.job_scope.update_all(failed_at: Time.current)

    assert_equal 0, TickJob.pending_count
    assert_equal 1, TickJob.failed_count

    TickJob.ensure_scheduled!

    assert_equal 1, TickJob.pending_count
    assert_equal 1, TickJob.failed_count
  end

  private

  def without_tick_side_effects
    server = Object.new
    server.define_singleton_method(:broadcast) { |_channel, _payload| }

    MarketPriceUpdater.stub(:update_prices!, nil) do
      ActionCable.stub(:server, server) do
        ShipArrivalJob.stub(:perform_now, nil) do
          ShipTravel.stub(:cleanup_stale_after_arrival!, nil) do
            yield
          end
        end
      end
    end
  end
end
