class TickRunner
  LOCK_KEY = 4_294_967_291

  def self.run_once!(job_id: nil)
    new(job_id: job_id).run_once!
  end

  def self.with_tick_lock
    connection = ActiveRecord::Base.connection

    if connection.adapter_name.match?(/postg/i)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
      return false unless ActiveModel::Type::Boolean.new.cast(locked)

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
      end
    else
      TickControl.with_instance_lock { yield }
    end
  end

  def initialize(job_id: nil)
    @job_id = job_id
  end

  def run_once!
    locked_result = self.class.with_tick_lock do
      control = TickControl.instance.reload
      if control.running?
        control.mark_tick_started!(job_id: @job_id)
        Rails.logger.info(log_line("increment_started"))

        Tick.increment!

        control.mark_tick_completed!
        Rails.logger.info(log_line("increment_completed"))
        :completed
      else
        Rails.logger.info(log_line("skipped", reason: "disabled"))
        :disabled
      end
    rescue => error
      control&.mark_tick_failed!(error)
      Rails.logger.error(log_line("increment_failed", error_class: error.class.name, error_message: error.message))
      raise
    end

    unless locked_result
      Rails.logger.info(log_line("lock_unavailable"))
      return :locked
    end

    locked_result
  end

  private

  def log_line(event, **extra)
    payload = {
      event: "tick_runner_#{event}",
      dyno: ENV["DYNO"],
      current_tick: safe_current_tick,
      seconds_per_tick: safe_seconds_per_tick
    }.merge(extra)

    payload.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")
  end

  def safe_current_tick
    Tick.limit(1).pick(:current_tick) || 0
  rescue
    "unknown"
  end

  def safe_seconds_per_tick
    Tick.seconds_per_tick
  rescue
    "unknown"
  end
end
