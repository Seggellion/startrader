if ENV["TICK_BOOTSTRAP"] == "true"
  Rails.application.config.after_initialize do
    next if defined?(Rake)

    begin
      next unless ActiveRecord::Base.connection.data_source_exists?("tick_controls")
      next unless TickControl.instance.running?

      TickWatchdogJob.ensure_scheduled!
      TickJob.ensure_scheduled!
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      Rails.logger.warn("event=\"tick_bootstrap_skipped\" error_class=#{error.class.name.inspect} error_message=#{error.message.inspect}")
    end
  end
end
