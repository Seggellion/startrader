class TravelArrivalEvent < ApplicationRecord
  after_create_commit :schedule_delivery
  after_update_commit :schedule_retry, if: -> { saved_change_to_attempts? && sent_at.nil? }
  scope :pending, -> { where(sent_at:nil) }

  def schedule_delivery
    TravelArrivalDispatchJob.perform_later
  rescue StandardError => error
    # Tick sweep independently discovers committed events if enqueue is lost.
    Rails.logger.error("event=arrival_enqueue_failed event_id=#{id} error_class=#{error.class.name}")
  end

  def schedule_retry
    TravelArrivalDispatchJob.set(wait_until:next_attempt_at).perform_later
  rescue StandardError => error
    Rails.logger.error("event=arrival_retry_enqueue_failed event_id=#{id} error_class=#{error.class.name}")
  end

  def deliver!
    # A transaction-scoped row lock is a crash-recoverable claim: process death
    # releases it. SKIP LOCKED lets other dispatchers continue without waiting.
    self.class.transaction do
      event=self.class.where(id:id,sent_at:nil).lock('FOR UPDATE SKIP LOCKED').first
      return unless event
      return if event.next_attempt_at && event.next_attempt_at > Time.current
      begin
        RabbitmqSender.send_arrival_event(event)
        event.update!(sent_at:Time.current,attempts:event.attempts+1,last_error_class:nil)
      rescue StandardError => error
        event.update!(attempts:event.attempts+1,last_error_class:error.class.name,
          next_attempt_at:Time.current+[2**[event.attempts,8].min,300].min.seconds)
        Rails.logger.error("event=arrival_delivery_failed event_id=#{event.id} error_class=#{error.class.name}")
      end
    end
  end
end
