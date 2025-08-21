# app/jobs/tick_job.rb
class TickJob < ApplicationJob
  queue_as :default

  def perform
    
    return unless TickControl.instance.running?

    Rails.logger.info "TickJob started."

    Tick.increment!
    # Tick.instance.process_tick

    Rails.logger.info "TickJob completed successfully."

    # keep the chain going while running
    self.class.set(wait: 30.seconds).perform_later if TickControl.instance.running?
  end

  # kick off one job if none queued
  def self.ensure_scheduled!
    return unless TickControl.instance.running?
    return unless pending_count.zero?
    perform_later
  end

  # stop future runs
  def self.cancel_all!
    Delayed::Job.where("handler LIKE '%job_class: TickJob%'").delete_all
  end

  def self.pending_count
    Delayed::Job.where("handler LIKE '%job_class: TickJob%'")
                .where(failed_at: nil)
                .count
  end
end
