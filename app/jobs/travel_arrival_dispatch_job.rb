class TravelArrivalDispatchJob < ApplicationJob
  queue_as :travel_notifications
  def perform
    # Deterministic bounded sweep; Tick runs this independently of enqueue callbacks.
    TravelArrivalEvent.pending.where('next_attempt_at IS NULL OR next_attempt_at <= ?',Time.current)
      .order(:id).limit(100).pluck(:id).each do |id|
      begin
        TravelArrivalEvent.find_by(id:id)&.deliver!
      rescue StandardError => error
        Rails.logger.error("event=arrival_dispatch_failed event_id=#{id} error_class=#{error.class.name}")
      end
    end
  end
end
