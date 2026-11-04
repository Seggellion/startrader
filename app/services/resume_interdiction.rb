# Explicit resume only: preserve the original identity, destination, cargo and
# broker. A signed review binds the operator to one observed pause cycle.
class ResumeInterdiction
  FIELDS = %w[from_location_id to_location_id departure_tick arrival_tick
    total_duration_ticks is_paused paused_at_tick remaining_ticks_from_arrival
    interdict_window_percent interdiction_count last_interdicted_tick
    completed_at_tick rabbitmq_environment].freeze
  Review = Struct.new(:allowed, :reason, :token, :duration_ticks, keyword_init: true)
  Result = Struct.new(:action, :replayed, keyword_init: true)

  def self.verifier
    Rails.application.message_verifier('resume-interdiction')
  end

  def self.block_reason(travel)
    return 'Journey is not paused.' unless travel.is_paused? && travel.completed_at_tick.nil?
    return 'Invalid timing or pause metadata needs review.' if TravelState.new(travel).invalid?
    return 'Multiple unfinished journeys need review.' unless
      ShipTravel.where(user_ship_id: travel.user_ship_id, completed_at_tick: nil).count == 1
    ship = travel.user_ship
    return 'Ship status differs from this interdiction.' unless ship.status == 'interdicted'
    return 'Ship location differs from the saved origin.' unless ship.location_name == travel.from_location.name
    player_name = ship.shard_user&.current_location_name
    return 'Player location is unknown; review is required.' if player_name.blank?
    return 'Player location differs from ship location; review is required.' unless player_name == ship.location_name

    nil
  end

  def self.fingerprint(travel)
    ship = travel.user_ship
    Digest::SHA256.hexdigest(JSON.generate([
      travel.attributes.slice(*FIELDS),
      travel.updated_at&.iso8601(6), ship.id, ship.status, ship.location_name,
      ship.shard_user_id, ship.shard_user&.current_location_name
    ]))
  end

  def self.review(travel)
    travel.reload
    reason = block_reason(travel)
    return Review.new(allowed: false, reason: reason) if reason

    token = verifier.generate(
      {id: travel.id, guid: travel.travel_guid, cycle: travel.interdiction_count,
       fingerprint: fingerprint(travel)}.stringify_keys,
      purpose: 'resume', expires_in: 30.minutes)
    Review.new(allowed: true, token: token,
      duration_ticks: [travel.remaining_ticks_from_arrival, 1].max)
  end

  def self.call(id:, review_token:, actor:, reason:, operator_reference: nil)
    admin = actor.is_a?(User) && actor.persisted? && actor.admin?
    operator = actor == :operator && operator_reference.present?
    raise TravelLifecycle::Error.new('unauthorized', 'Administrator access is required.') unless admin || operator
    reason = reason.to_s.strip
    unless (3..1000).cover?(reason.length)
      raise TravelLifecycle::Error.new('reason_required', 'Enter a reason between 3 and 1000 characters.')
    end
    data = verifier.verified(review_token, purpose: 'resume') if review_token.is_a?(String)
    unless data && data['id'] == id.to_i
      raise TravelLifecycle::Error.new('stale_review', 'This review expired or is invalid. Refresh the journey and review it again.')
    end
    existing = TravelResumeAction.find_by(travel_guid: data['guid'], interdiction_count: data['cycle'])
    return Result.new(action: existing, replayed: true) if existing

    travel = ShipTravel.find(id)
    TravelLifecycle.with_ship(travel.user_ship) do
      travel.lock!
      existing = TravelResumeAction.find_by(travel_guid: data['guid'], interdiction_count: data['cycle'])
      next Result.new(action: existing, replayed: true) if existing
      unless travel.travel_guid == data['guid'] && fingerprint(travel) == data['fingerprint']
        raise TravelLifecycle::Error.new('stale_review', 'The journey changed since review. Refresh and review it again.')
      end
      if (blocked = block_reason(travel))
        raise TravelLifecycle::Error.new('resume_blocked', blocked)
      end
      tick = Tick.order(:id).pick(:current_tick)
      raise TravelLifecycle::Error.new('invalid_state', 'Current server tick is unavailable.') unless tick.is_a?(Integer) && tick >= 0

      before = travel.attributes.slice(*FIELDS)
      travel.resume!(tick)
      action = TravelResumeAction.create!(
        travel_guid: travel.travel_guid, ship_travel_id: travel.id, user_ship_id: travel.user_ship_id,
        interdiction_count: travel.interdiction_count, last_interdicted_tick: travel.last_interdicted_tick,
        actor_kind: admin ? 'admin' : 'operator', admin_user: admin ? actor : nil,
        actor_label: admin ? actor.username : operator_reference.to_s.first(200),
        reason: reason, resumed_at_tick: tick, remaining_ticks: travel.total_duration_ticks,
        arrival_tick: travel.arrival_tick, rabbitmq_environment: travel.rabbitmq_environment,
        before_state: before, after_state: travel.attributes.slice(*FIELDS))
      Result.new(action: action, replayed: false)
    end
  rescue ActiveRecord::RecordNotFound
    existing = TravelResumeAction.find_by(travel_guid: data&.[]('guid'), interdiction_count: data&.[]('cycle'))
    return Result.new(action: existing, replayed: true) if existing

    raise
  end
end
