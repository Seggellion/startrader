class TickWatchdogJob < ApplicationJob
  queue_as :default

  WATCHDOG_INTERVAL = 30.seconds

  def perform
    control = TickControl.instance
    unless control.running?
      Rails.logger.info(self.class.watchdog_log("skipped", reason: "disabled"))
      TickJob.cancel_all!
      return
    end

    recovered = recover_tick_chain_if_needed(control)
    control.mark_recovered! if recovered
  rescue => error
    Rails.logger.error(self.class.watchdog_log("failed", error_class: error.class.name, error_message: error.message))
    raise
  ensure
    self.class.schedule_next_if_running!
  end

  def self.ensure_scheduled!(force: false, wait: WATCHDOG_INTERVAL)
    TickControl.with_instance_lock do |control|
      return :disabled unless control.running?
      return :already_scheduled if !force && pending_count.positive?

      set(wait: wait).perform_later
      Rails.logger.info(watchdog_log("scheduled", wait_seconds: wait.to_i, force: force))
      :scheduled
    end
  end

  def self.schedule_next_if_running!
    TickControl.with_instance_lock do |control|
      return :disabled unless control.running?
      return :already_scheduled if future_count.positive?

      set(wait: WATCHDOG_INTERVAL).perform_later
      Rails.logger.info(watchdog_log("next_scheduled", wait_seconds: WATCHDOG_INTERVAL.to_i))
      :scheduled
    end
  rescue => error
    Rails.logger.error(watchdog_log("schedule_failed", error_class: error.class.name, error_message: error.message))
    raise
  end

  def self.cancel_all!
    deleted = job_scope.delete_all
    Rails.logger.info(watchdog_log("cancelled", deleted_jobs: deleted))
    deleted
  end

  def self.pending_count
    job_scope.where(failed_at: nil).count
  end

  def self.future_count
    job_scope.where(failed_at: nil).where("run_at > ?", Time.current).count
  end

  def self.failed_count
    job_scope.where.not(failed_at: nil).count
  end

  def self.job_scope
    Delayed::Job.where(
      "handler LIKE :plain OR handler LIKE :quoted OR handler LIKE :class_name",
      plain: "%job_class: TickWatchdogJob%",
      quoted: "%job_class: \"TickWatchdogJob\"%",
      class_name: "%TickWatchdogJob%"
    )
  end

  def self.watchdog_log(event, **extra)
    payload = {
      event: "tick_watchdog_#{event}",
      dyno: ENV["DYNO"],
      current_tick: safe_current_tick,
      pending_tick_jobs: TickJob.pending_count,
      failed_tick_jobs: TickJob.failed_count
    }.merge(extra)

    payload.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")
  rescue => error
    "event=#{event.inspect} log_error=#{error.class.name.inspect}"
  end

  private

  def recover_tick_chain_if_needed(control)
    if TickJob.pending_count.zero?
      Rails.logger.warn(self.class.watchdog_log("recovering", reason: "missing_tick_job"))
      TickJob.ensure_scheduled!(force: true)
      return true
    end

    if control.stale? && TickJob.ready_count.zero?
      Rails.logger.warn(self.class.watchdog_log("recovering", reason: "stale_heartbeat"))
      TickJob.ensure_scheduled!(force: true)
      return true
    end

    Rails.logger.info(self.class.watchdog_log("healthy", last_heartbeat_at: control.last_heartbeat_at))
    false
  end

  def self.safe_current_tick
    Tick.limit(1).pick(:current_tick) || 0
  rescue
    "unknown"
  end
end
