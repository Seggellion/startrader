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
    unless receipt.user_ship_id == ship.id && receipt.request_context == context.deep_stringify_keys
      raise TravelLifecycle::Error.new('request_conflict','Travel request identifier conflicts with an earlier request.')
    end
    travel=ShipTravel.find_by(travel_guid:guid) || ShipTravel.instantiate(receipt.travel_snapshot)
    travel.request_replayed=true
    travel.request_outcome=receipt.outcome
    travel
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
