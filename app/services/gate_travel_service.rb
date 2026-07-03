class GateTravelService
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
    keyword_init: true
  )

  def initialize(ship_guid:, gateway_name: nil, travel_guid: nil, start_tick: nil)
    @ship_guid = ship_guid
    @gateway_name = gateway_name
    @travel_guid = travel_guid.presence || SecureRandom.uuid
    @start_tick = start_tick
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

    availability = ShipAvailability.new(shard_user: user_ship.shard_user, user_ship: user_ship).validate_usable!
    current_location = availability.ship_location
    raise StandardError, "Current location not found for ship_guid #{ship_guid}" unless current_location

    origin_location = resolved_origin_gateway(current_location)
    validate_gateway_location!(origin_location)

    origin_star_system = origin_location.star_system_name.to_s.strip
    target_star_system = target_star_system_from(origin_location)
    arrival_gateway_name = "#{origin_star_system} Gateway"
    arrival_location = resolve_gateway!(arrival_gateway_name, target_star_system)

    travel = create_gate_travel!(
      user_ship: user_ship,
      origin_location: origin_location,
      arrival_location: arrival_location
    )

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
      travel_time_seconds: TRAVEL_TIME_SECONDS
    )
  end

  private

  attr_reader :ship_guid, :gateway_name, :travel_guid, :start_tick

  def resolved_shard_for(user_ship)
    user_ship.shard || user_ship.shard_user&.shard || Shard.find_by(name: user_ship.shard_name)
  end

  def validate_gateway_location!(location)
    return if gateway_location?(location)

    raise StandardError, "You are not at a valid Jumpgate location."
  end

  def resolved_origin_gateway(current_location)
    return current_location if gateway_name.blank?

    LocationResolver.find_in_star_system!(
      input_name: gateway_name,
      star_system_name: current_location.star_system_name
    )
  rescue ActiveRecord::RecordNotFound
    raise StandardError, "Gateway #{gateway_name} is not available from #{current_location.star_system_name}."
  end

  def target_star_system_from(location)
    normalized_name = normalized_gateway_name(location.name)
    target = normalized_name.delete_suffix(GATEWAY_SUFFIX).strip
    raise StandardError, "No valid destination Jumpgate found." if target.blank? || target == normalized_name

    target
  end

  def resolve_gateway!(name, star_system_name)
    LocationResolver.find_in_star_system!(
      input_name: name,
      star_system_name: star_system_name
    )
  rescue ActiveRecord::RecordNotFound => e
    if e.message.start_with?("Multiple locations match")
      raise StandardError, "Multiple destination Jumpgates match #{name} in #{star_system_name}."
    end

    raise StandardError, "No valid destination Jumpgate found."
  end

  def create_gate_travel!(user_ship:, origin_location:, arrival_location:)
    raise StandardError, "Already in transit" if user_ship.active_travel.present?

    current_tick = start_tick || Tick.current
    duration_ticks = gate_travel_duration_ticks

    ShipTravel.transaction do
      travel = ShipTravel.create!(
        user_ship: user_ship,
        from_location: origin_location,
        to_location: arrival_location,
        travel_guid: travel_guid,
        departure_tick: current_tick,
        arrival_tick: current_tick + duration_ticks,
        total_duration_ticks: duration_ticks,
        interdict_window_percent: Setting.get("interdiction_window_percent").presence || TravelService::DEFAULT_WINDOW_PERCENT,
        ship_travel_type: "gate_travel"
      )

      user_ship.update!(location_name: origin_location.name, status: "in_transit")
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
