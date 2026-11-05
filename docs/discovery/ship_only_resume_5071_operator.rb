# Operator-only helper. The production wrapper pins this exception to journey 5071.
# This does not relax ResumeInterdiction's admin/API policy.
class ResumeSeparatedInterdiction
  def self.call(plan:, reference:, reason:)
    original=plan.fetch('travel')
    existing=TravelResumeAction.find_by(travel_guid:original.fetch('travel_guid'),
      interdiction_count:original.fetch('interdiction_count'))
    if existing
      raise 'Existing action does not match this approved exception' unless
        existing.actor_kind=='operator' && existing.actor_label==reference &&
        existing.before_state['location_exception']&.[]('player_location')==plan.fetch('player_location')
      return ResumeInterdiction::Result.new(action:existing,replayed:true)
    end
    travel=ShipTravel.find(original.fetch('id'))
    TravelLifecycle.with_ship(travel.user_ship) do
      travel.lock!
      ship=travel.user_ship
      player=ship.shard_user
      raise 'Identity changed' unless ship.id==plan.fetch('ship_id') &&
        ship.user_id==plan.fetch('user_id') && player&.id==plan.fetch('player_id')
      raise 'Pause changed' unless ResumeInterdiction.fingerprint(travel)==plan.fetch('fingerprint')
      raise 'Expected location separation changed' unless player.current_location_name==plan.fetch('player_location') &&
        ship.location_name==plan.fetch('ship_location') && player.current_location_name!=ship.location_name
      raise 'Another eligibility check failed' unless
        ResumeInterdiction.block_reason(travel)=='Player location differs from ship location; review is required.'
      tick=Tick.order(:id).pick(:current_tick)
      raise 'Current tick unavailable' unless tick.is_a?(Integer) && tick>=0
      player_before=player.attributes
      ship_location=ship.location_name
      exception={'player_id'=>player.id,'player_location'=>player.current_location_name,
        'ship_origin'=>ship_location,'player_moved'=>false,
        'scope'=>'Owner-approved ship-only resume; preserve the separated player location.'}
      before=travel.attributes.slice(*ResumeInterdiction::FIELDS).merge('location_exception'=>exception)
      travel.resume!(tick)
      raise 'Player moved during ship-only resume' unless player.reload.attributes==player_before
      raise 'Ship was relocated during resume' unless ship.reload.location_name==ship_location
      action=TravelResumeAction.create!(
        travel_guid:travel.travel_guid,ship_travel_id:travel.id,user_ship_id:ship.id,
        interdiction_count:travel.interdiction_count,last_interdicted_tick:travel.last_interdicted_tick,
        actor_kind:'operator',actor_label:reference,reason:reason,resumed_at_tick:tick,
        remaining_ticks:travel.total_duration_ticks,arrival_tick:travel.arrival_tick,
        rabbitmq_environment:travel.rabbitmq_environment,before_state:before,
        after_state:travel.attributes.slice(*ResumeInterdiction::FIELDS).merge('location_exception'=>exception))
      ResumeInterdiction::Result.new(action:action,replayed:false)
    end
  end
end
