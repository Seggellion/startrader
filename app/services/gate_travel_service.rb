class GateTravelService
  class IntentError < TravelLifecycle::Error
    attr_reader :state
    def initialize(code, message, state)
      @state = state
      super(code, message)
    end
  end

  TRAVEL_TIME_SECONDS = 120
  GATEWAY_SUFFIX = " Gateway"

  Result = Struct.new(
    :user_ship,
    :user,
    :ship,
    :shard,
    :origin_location,
    :arrival_location,
    :origin_star_system,
    :target_star_system,
    :travel,
    :travel_time_seconds,
    :routing_source,
    keyword_init: true
  )

  def initialize(ship_guid:, gateway_name: nil, travel_guid: nil, start_tick: nil, rabbitmq_environment: nil, expected_origin_location: nil, expected_destination_location: nil)
    @ship_guid = ship_guid
    @gateway_name = gateway_name
    @travel_guid = travel_guid.presence || SecureRandom.uuid
    @start_tick = start_tick
    @requested_rabbitmq_environment = RabbitmqConnection.normalize(rabbitmq_environment)
    @rabbitmq_environment = RabbitmqConnection.normalize!(rabbitmq_environment)
    @expected_origin_location = expected_origin_location.presence
    @expected_destination_location = expected_destination_location.presence
  end

  def call
    raise StandardError, "ship_guid is required" if ship_guid.blank?

    user_ship = UserShip.includes(:user, :ship, :shard, shard_user: :shard).find_by(guid: ship_guid)
    raise StandardError, "No user ship found for ship_guid #{ship_guid}" unless user_ship

    user = user_ship.user
    ship = user_ship.ship
    shard = resolved_shard_for(user_ship)

    raise StandardError, "No user found for ship_guid #{ship_guid}" unless user
    raise StandardError, "No ship found for ship_guid #{ship_guid}" unless ship
    raise StandardError, "No shard found for ship_guid #{ship_guid}" unless shard

    intent_error = nil
    result = TravelLifecycle.with_ship(user_ship) do
      selection = GateTravelRouting.resolve(user_ship:user_ship,shard:shard,travel_guid:travel_guid,
        requested_environment:@requested_rabbitmq_environment)
      @rabbitmq_environment = selection.environment
      context = {kind:'gate_travel', gateway:TravelRequestReceipt.normalize_name(gateway_name),
        rabbitmq_environment:rabbitmq_environment}
      context[:expected_origin_location] = expected_origin_location.to_s.strip.downcase.squish if expected_origin_location
      context[:expected_destination_location] = expected_destination_location.to_s.strip.downcase.squish if expected_destination_location
      if (replay = TravelRequestReceipt.replay!(travel_guid,user_ship,context))
        return Result.new(user_ship:user_ship,user:user,ship:ship,shard:shard,
          origin_location:replay.from_location,arrival_location:replay.to_location,
          origin_star_system:replay.from_location.star_system_name,target_star_system:replay.to_location.star_system_name,
          travel:replay,travel_time_seconds:TRAVEL_TIME_SECONDS,routing_source:selection.source)
      end
      availability = ShipAvailability.new(shard_user: user_ship.shard_user, user_ship: user_ship).validate_usable!
      current_location = availability.ship_location
      raise StandardError, "Current location not found for ship_guid #{ship_guid}" unless current_location

      origin_location = resolved_origin_gateway(current_location)
      validate_gateway_location!(origin_location)

      origin_star_system = origin_location.star_system_name.to_s.strip
      target_star_system = target_star_system_from(origin_location)
      arrival_gateway_name = "#{origin_star_system} Gateway"
      arrival_location = resolve_gateway!(arrival_gateway_name, target_star_system)

      validate_intent!(user_ship, current_location, arrival_location)

      TravelRequestReceipt.lock_guid!(travel_guid)
      travel = TravelRequestReceipt.replay!(travel_guid,user_ship,context) || create_gate_travel!(
        user_ship: user_ship,
        origin_location: origin_location,
        arrival_location: arrival_location
      )

      TravelRequestReceipt.record!(travel,context) unless travel.request_replayed

      Result.new(
        user_ship: user_ship,
        user: user,
        ship: ship,
        shard: shard,
        origin_location: origin_location,
        arrival_location: arrival_location,
        origin_star_system: origin_star_system,
        target_star_system: target_star_system,
        travel: travel,
        travel_time_seconds: TRAVEL_TIME_SECONDS,
        routing_source: selection.source
      )
    rescue IntentError => error
      # A due arrival discovered by this request is a completed movement of its
      # own. Commit that arrival, then refuse the ambiguous new departure.
      intent_error = error
      nil
    end
    raise intent_error if intent_error
    result
  end

  private

  attr_reader :ship_guid, :gateway_name, :travel_guid, :start_tick, :rabbitmq_environment,
    :expected_origin_location, :expected_destination_location

  def validate_intent!(user_ship, current_location, arrival_location)
    state = {user_ship_id:user_ship.id, current_location:current_location.name, player_location:user_ship.shard_user&.current_location_name,
      current_star_system:current_location.star_system_name, proposed_destination:arrival_location.name,
      proposed_star_system:arrival_location.star_system_name}
    if expected_origin_location && !matches_intent_location?(expected_origin_location, current_location)
      raise IntentError.new('stale_jump_origin',
        "Jump was not started. Ship is at #{current_location.name}; refresh its location before jumping.", state)
    end
    if expected_destination_location && !matches_intent_location?(expected_destination_location, arrival_location)
      raise IntentError.new('jump_destination_mismatch',
        "Jump was not started. This gateway leads to #{arrival_location.name}; confirm the intended destination.", state)
    end
    return if gateway_name.present? || expected_origin_location || expected_destination_location

    latest = TravelRequestReceipt.where(user_ship_id:user_ship.id, outcome:'completed')
      .order(completed_at_tick: :desc, id: :desc).first
    return unless latest && latest.travel_snapshot['ship_travel_type'] == 'gate_travel' &&
      latest.travel_snapshot['to_location_id'].to_i == current_location.id

    raise IntentError.new('jump_destination_required',
      "Previous jump already completed at #{current_location.name}. Jump was not started. " \
      "Choose a gateway for a new trip, or retry the original travel_guid to retrieve its result.",
      state.merge(previous_travel_guid:latest.travel_guid, lifecycle_status:'completed',
        route_confirmation_required:true))
  end

  def matches_intent_location?(input, location)
    # Preconditions are canonical names, never fuzzy searches that could resolve
    # a stale gateway in another system to the current gateway.
    input.to_s.strip.downcase.squish == location.name.to_s.strip.downcase.squish
  end

  def find_named_gateway!(input_name:, star_system_name:)
    LocationResolver.find_named_in_star_system(input_name:input_name, star_system_name:star_system_name) ||
      raise(ActiveRecord::RecordNotFound, "Location not found in #{star_system_name}.")
  end

  def resolved_shard_for(user_ship)
    user_ship.shard || user_ship.shard_user&.shard || Shard.find_by(name: user_ship.shard_name)
  end

  def validate_gateway_location!(location)
    return if gateway_location?(location)

    raise StandardError, "You are not at a valid Jumpgate location."
  end

  def resolved_origin_gateway(current_location)
    return current_location if gateway_name.blank?

    find_named_gateway!(
      input_name: gateway_name,
      star_system_name: current_location.star_system_name
    )
  rescue ActiveRecord::RecordNotFound
    raise StandardError, "Gateway #{gateway_name} is not available from #{current_location.star_system_name}."
  end

  def target_star_system_from(location)
    normalized_name = normalized_gateway_name(location.name)
    target = normalized_name.delete_suffix(GATEWAY_SUFFIX).strip
    raise TravelLifecycle::Error.new("route_unavailable", "No valid destination Jumpgate found.") if target.blank? || target == normalized_name

    target
  end

  def resolve_gateway!(name, star_system_name)
    find_named_gateway!(
      input_name: name,
      star_system_name: star_system_name
    )
  rescue ActiveRecord::RecordNotFound => e
    if e.message.start_with?("Multiple locations match")
      raise StandardError, "Multiple destination Jumpgates match #{name} in #{star_system_name}."
    end

    raise TravelLifecycle::Error.new("route_unavailable", "No valid destination Jumpgate found.")
  end

  def create_gate_travel!(user_ship:, origin_location:, arrival_location:)
    current_tick = start_tick || Tick.current
    TravelLifecycle.assert_free!(user_ship,current_tick)
    duration_ticks = gate_travel_duration_ticks

    ShipTravel.transaction do
      travel = ShipTravel.create!(
        user_ship: user_ship,
        from_location: origin_location,
        to_location: arrival_location,
        travel_guid: travel_guid,
        departure_tick: current_tick,
        arrival_tick: TravelLifecycle.deadline!(current_tick, duration_ticks),
        total_duration_ticks: duration_ticks,
        interdict_window_percent: Setting.get("interdiction_window_percent").presence || TravelService::DEFAULT_WINDOW_PERCENT,
        rabbitmq_environment: rabbitmq_environment,
        ship_travel_type: "gate_travel"
      )

      user_ship.update!(location_name: origin_location.name, status: "in_transit")
      user_ship.shard_user&.update_current_location!(origin_location)
      travel
    end
  end

  def gate_travel_duration_ticks
    seconds_per_tick = Tick.seconds_per_tick.to_f
    seconds_per_tick = Tick::DEFAULT_SECONDS_PER_TICK if seconds_per_tick <= 0

    (TRAVEL_TIME_SECONDS / seconds_per_tick).ceil
  end

  def gateway_location?(location)
    normalized_gateway_name(location.name).end_with?(GATEWAY_SUFFIX)
  end

  def normalized_gateway_name(value)
    value.to_s.strip.sub(/\s*\([^)]*\)\s*\z/, "")
  end
end
