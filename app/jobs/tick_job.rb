# app/jobs/tick_job.rb
class TickJob < ApplicationJob
  queue_as :default

  def perform
    control = TickControl.instance
    unless control.running?
      Rails.logger.info(self.class.tick_log("skipped", reason: "disabled"))
      return
    end

    Rails.logger.info(self.class.tick_log("started"))

    TickRunner.run_once!(job_id: job_id)

    Rails.logger.info(self.class.tick_log("completed"))
  rescue => error
    Rails.logger.error(self.class.tick_log("failed", error_class: error.class.name, error_message: error.message))

    # The next tick is scheduled in ensure. Let the watchdog and heartbeat expose
    # repeated failures without turning one bad tick into a dead chain.
    nil
  ensure
    self.class.schedule_next_if_running!
  end

  def self.ensure_scheduled!(force: false, wait: 0.seconds)
    TickControl.with_instance_lock do |control|
      return :disabled unless control.running?
      return :already_scheduled if !force && pending_count.positive?

      set(wait: wait).perform_later
      Rails.logger.info(tick_log("scheduled", wait_seconds: wait.to_i, force: force))
      :scheduled
    end
  end

  def self.schedule_next_if_running!
    wait = Tick.seconds_per_tick.seconds

    TickControl.with_instance_lock do |control|
      return :disabled unless control.running?
      return :already_scheduled if future_count.positive?

      set(wait: wait).perform_later
      Rails.logger.info(tick_log("next_scheduled", wait_seconds: wait.to_i))
      :scheduled
    end
  rescue => error
    Rails.logger.error(tick_log("schedule_failed", error_class: error.class.name, error_message: error.message))
    raise
  end

  def self.cancel_all!
    deleted = job_scope.delete_all
    Rails.logger.info(tick_log("cancelled", deleted_jobs: deleted))
    deleted
  end

  def self.pending_count
    job_scope.where(failed_at: nil).count
  end

  def self.future_count
    job_scope.where(failed_at: nil).where("run_at > ?", Time.current).count
  end

  def self.ready_count
    job_scope.where(failed_at: nil)
             .where(locked_at: nil)
             .where("run_at IS NULL OR run_at <= ?", Time.current)
             .count
  end

  def self.failed_count
    job_scope.where.not(failed_at: nil).count
  end

  def self.job_scope
    Delayed::Job.where(
      "handler LIKE :plain OR handler LIKE :quoted OR handler LIKE :class_name",
      plain: "%job_class: TickJob%",
      quoted: "%job_class: \"TickJob\"%",
      class_name: "%TickJob%"
    )
  end

  def self.tick_log(event, **extra)
    payload = {
      event: "tick_job_#{event}",
      dyno: ENV["DYNO"],
      current_tick: safe_current_tick,
      seconds_per_tick: safe_seconds_per_tick,
      pending_tick_jobs: safe_count(:pending_count),
      failed_tick_jobs: safe_count(:failed_count),
      last_tick_completed_at: TickControl.instance.last_tick_completed_at
    }.merge(extra)

    payload.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")
  end

  def self.safe_count(method_name)
    public_send(method_name)
  rescue
    "unknown"
  end

  def self.safe_current_tick
    Tick.limit(1).pick(:current_tick) || 0
  rescue
    "unknown"
  end

  def self.safe_seconds_per_tick
    Tick.seconds_per_tick
  rescue
    "unknown"
  end
end
