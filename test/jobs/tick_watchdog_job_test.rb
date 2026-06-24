require "test_helper"

class TickWatchdogJobTest < ActiveSupport::TestCase
  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :delayed_job

    Delayed::Job.delete_all
    TickControl.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end
  end

  teardown do
    Delayed::Job.delete_all
    TickControl.delete_all
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  test "enqueues a tick job when running and none exists" do
    TickControl.instance.update!(running: true)

    TickWatchdogJob.perform_now

    assert_equal 1, TickJob.pending_count
    assert_equal 1, TickWatchdogJob.pending_count
  end

  test "does nothing except cleanup when disabled" do
    TickControl.instance.update!(running: false)
    TickJob.perform_later

    TickWatchdogJob.perform_now

    assert_equal 0, TickJob.pending_count
    assert_equal 0, TickWatchdogJob.pending_count
  end

  test "stale heartbeat causes recovery even when a future tick exists" do
    control = TickControl.instance
    control.update!(running: true, last_heartbeat_at: 1.hour.ago)
    TickJob.set(wait: 1.hour).perform_later

    TickWatchdogJob.perform_now

    assert_equal 2, TickJob.pending_count
    assert control.reload.last_recovered_at.present?
  end
end
