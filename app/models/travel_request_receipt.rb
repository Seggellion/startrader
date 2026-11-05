class TravelRequestReceipt < ApplicationRecord
  # No expiry in this release: request identity remains reserved after completion.
  def self.normalize_name(value)
    value.to_s.strip.sub(/\s*\([^)]*\)\s*\z/, '').downcase.squish
  end

  def self.lock_guid!(guid)
    quoted=connection.quote(guid.to_s)
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{quoted}, 0))")
  end

  def self.replay!(guid, ship, context)
    receipt=find_by(travel_guid:guid)
    unless receipt
      if ShipTravel.exists?(travel_guid:guid)
        raise TravelLifecycle::Error.new('request_conflict','Legacy travel identifier is already reserved; original request context is unavailable.')
      end
      return
    end
    lock_guid!(guid)
    receipt.reload
    unless receipt.user_ship_id == ship.id && receipt.matches_context?(context)
      raise TravelLifecycle::Error.new('request_conflict','Travel request identifier conflicts with an earlier request.')
    end
    travel=ShipTravel.find_by(travel_guid:guid) || ShipTravel.instantiate(receipt.travel_snapshot)
    travel.request_replayed=true
    travel.request_outcome=receipt.outcome
    travel
  end

  def matches_context?(context)
    requested = context.deep_stringify_keys
    return true if request_context == requested
    # Gate receipts created before explicit broker selection had only kind/gateway.
    # Their saved broker remains authoritative; never rewrite or reroute them.
    request_context['kind'] == 'gate_travel' &&
      !request_context.key?('rabbitmq_environment') &&
      requested.except('rabbitmq_environment') == request_context &&
      requested['rabbitmq_environment'] == RabbitmqConnection.normalize!(travel_snapshot['rabbitmq_environment'])
  end

  def self.record!(travel, context)
    create!(travel_guid:travel.travel_guid,user_ship_id:travel.user_ship_id,
      request_context:context,travel_snapshot:travel.attributes)
  end

  def self.finish!(travel, outcome, tick)
    lock_guid!(travel.travel_guid)
    receipt=find_or_initialize_by(travel_guid:travel.travel_guid)
    if receipt.new_record?
      receipt.assign_attributes(user_ship_id:travel.user_ship_id,request_context:{legacy:true},travel_snapshot:travel.attributes)
    end
    unless receipt.user_ship_id==travel.user_ship_id
      raise TravelLifecycle::Error.new('request_conflict','Travel identity needs review.')
    end
    receipt.update!(outcome:outcome,completed_at_tick:tick,travel_snapshot:travel.attributes)
  end
end
