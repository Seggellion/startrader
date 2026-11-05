require 'json'
require 'digest'
require 'time'

# One-off operator delivery, never called by normal requests or background jobs.
# Source journey/event rows and the original broker queue remain untouched.
class ReviewedArrivalCatchup
  def self.review(plan:)
    event=TravelArrivalEvent.find(plan.fetch(:event_id))
    receipt=TravelRequestReceipt.find(plan.fetch(:receipt_id))
    ship=UserShip.find(plan.fetch(:ship_id))
    player=ship.shard_user
    raise 'Arrival identity changed' unless receipt.user_ship_id==plan.fetch(:ship_id) &&
      receipt.travel_guid==event.travel_guid && event.rabbitmq_environment=='prod' && event.sent_at &&
      receipt.outcome=='completed' && receipt.travel_snapshot['to_location_id']==plan.fetch(:to_location_id) &&
      ship.user_id==plan.fetch(:user_id) && ship.shard_id==plan.fetch(:shard_id) && player&.id==plan.fetch(:player_id)
    raise 'Player or ship has moved since the completed arrival' unless
      ship.location_name==plan.fetch(:destination) && player.current_location_name==ship.location_name &&
      !ship.ship_travels.where(completed_at_tick:nil).exists? && ship.status=='docked'
    raise 'A newer completed journey exists' unless TravelRequestReceipt.where(user_ship_id:ship.id,outcome:'completed')
      .order(completed_at_tick: :desc,id: :desc).pick(:id)==receipt.id
    fields=event.payload.fetch('fields')
    raise 'Saved event identities differ' unless fields[2]==ship.user.uid && fields[7]==ship.guid &&
      fields[5]==ship.shard.channel_uuid && fields[12]==receipt.travel_guid &&
      fields[10]==plan.fetch(:origin) && fields[11]==plan.fetch(:destination) &&
      event.payload['routing_key']=='maidenb0tevents.seggellion'
    rows=[event.attributes,receipt.attributes,ship.attributes,player.attributes]
    {fingerprint:Digest::SHA256.hexdigest(JSON.generate(rows)),
     event:event,receipt:receipt,ship:ship,player:player}
  end

  def self.deliver!(fingerprint:,journal:,reason:,plan:)
    raise 'Explicit owner authorization reason is required' if reason.to_s.strip.empty?
    TravelLifecycle.with_ship(UserShip.find(plan.fetch(:ship_id))) do
      current=review(plan:plan)
      raise 'Reviewed state changed; no catch-up sent' unless current[:fingerprint]==fingerprint
      record={event_id:plan.fetch(:event_id),receipt_id:plan.fetch(:receipt_id),ship_id:plan.fetch(:ship_id),reason:reason,
        started_at_utc:Time.now.utc.iso8601,state:'publish_started',source_broker:'prod',delivery_broker:'dev',
        source_fingerprint:fingerprint,message_identity:'Reuse original event_guid and travel_guid.'}
      # A started or uncertain attempt is never silently retried.
      File.open(journal,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate(record))}
      begin
        copy=current[:event].dup
        copy.rabbitmq_environment='dev'
        RabbitmqSender.send_arrival_event(copy)
        record.merge!(state:'broker_confirmed',confirmed_at_utc:Time.now.utc.iso8601)
        raise 'Source rows unexpectedly changed' unless review(plan:plan)[:fingerprint]==fingerprint
        File.write(journal,JSON.pretty_generate(record))
        record
      rescue Exception=>error
        record.merge!(state:'uncertain_or_failed',error_class:error.class.name)
        File.write(journal,JSON.pretty_generate(record))
        raise
      end
    end
  end
end
