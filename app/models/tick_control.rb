class TickControl < ApplicationRecord
  SINGLETON_KEY = 1
  STALE_HEARTBEAT_THRESHOLD = 30.seconds

  def self.instance
    find_or_create_by!(singleton_key: SINGLETON_KEY) do |control|
      control.running = false
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(singleton_key: SINGLETON_KEY)
  end

  def self.with_instance_lock
    transaction do
      control = instance.lock!
      yield control
    end
  end

  def running? = !!self[:running]

  def start!
    update!(
      running: true,
      last_tick_error: nil,
      last_tick_error_class: nil
    )

    TickWatchdogJob.ensure_scheduled!
    TickJob.ensure_scheduled!
  end

  def stop!
    update!(running: false)
    TickJob.cancel_all!
    TickWatchdogJob.cancel_all!
  end

  def mark_tick_started!(job_id: nil)
    update_columns(
      last_tick_started_at: Time.current,
      last_heartbeat_at: Time.current,
      last_tick_job_id: job_id,
      updated_at: Time.current
    )
  end

  def mark_tick_completed!
    update_columns(
      last_tick_completed_at: Time.current,
      last_heartbeat_at: Time.current,
      last_tick_error: nil,
      last_tick_error_class: nil,
      failure_count: 0,
      updated_at: Time.current
    )
  end

  def mark_tick_failed!(error)
    update_columns(
      last_tick_failed_at: Time.current,
      last_heartbeat_at: Time.current,
      last_tick_error: error.message.to_s.truncate(10_000),
      last_tick_error_class: error.class.name,
      failure_count: failure_count.to_i + 1,
      updated_at: Time.current
    )
  end

  def mark_recovered!
    update_columns(
      last_recovered_at: Time.current,
      last_heartbeat_at: Time.current,
      updated_at: Time.current
    )
  end

  def stale?(threshold: STALE_HEARTBEAT_THRESHOLD)
    last_heartbeat_at.blank? || last_heartbeat_at < threshold.ago
  end

  def health
    {
      running: running?,
      current_tick: Tick.current,
      pending_tick_jobs: TickJob.pending_count,
      failed_tick_jobs: TickJob.failed_count,
      pending_watchdog_jobs: TickWatchdogJob.pending_count,
      failed_watchdog_jobs: TickWatchdogJob.failed_count,
      last_tick_started_at: last_tick_started_at,
      last_tick_completed_at: last_tick_completed_at,
      last_tick_failed_at: last_tick_failed_at,
      last_heartbeat_at: last_heartbeat_at,
      last_recovered_at: last_recovered_at,
      failure_count: failure_count,
      last_tick_error_class: last_tick_error_class,
      last_tick_error: last_tick_error
    }
  end
end
