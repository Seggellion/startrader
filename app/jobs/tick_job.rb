class TickJob < ApplicationJob
    queue_as :default
  
    def perform
      if TickJob.already_enqueued?
        Rails.logger.info "Skipping TickJob because one is already enqueued."
        return
      end
  
      Rails.logger.info "TickJob started."
  
      Tick.increment!
    #  Tick.instance.process_tick
  
      Rails.logger.info "TickJob completed successfully."
  
      self.class.set(wait: 30.seconds).perform_later
    end
  
    # Check if a TickJob is already enqueued in the delayed_jobs table
    def self.already_enqueued?
      Delayed::Job.where(queue: "default", failed_at: nil).exists?
    end
  end
  