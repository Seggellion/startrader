class ShipAvailability
  Result = Struct.new(:available, :reason, :player_location, :ship_location, :in_transit, keyword_init: true)

  def initialize(shard_user:, user_ship:, current_tick: Tick.current)
    @shard_user = shard_user
    @user_ship = user_ship
    @current_tick = current_tick
  end

  def status
    process_due_arrival!
    user_ship.reload
    shard_user&.reload

    player_location = ensure_player_location_from_ship
    ship_location = user_ship.location || Location.find_by(name: user_ship.location_name)
    in_transit = in_transit?

    reason =
      if in_transit
        "Ship is already in transit."
      elsif player_location.nil?
        "Player location is unknown; initialize current location  with *status before use."
      elsif ship_location.nil?
        "Ship location is unknown; initialize the ship with *status before use."
      elsif ship_location.id != player_location.id
        "Ship is at #{ship_location.name}, but player is at #{player_location.name}."
      end

    Result.new(
      available: reason.nil?,
      reason: reason,
      player_location: player_location,
      ship_location: ship_location,
      in_transit: in_transit
    )
  end

  def validate_usable!
    result = status
    unless result.available
      TravelLifecycle.assert_free!(user_ship,current_tick) if result.in_transit
      raise TravelLifecycle::Error.new('location_mismatch',result.reason)
    end

    result
  end

  def in_transit?
    user_ship.ship_travels
             .where(completed_at_tick: nil)
             .exists?
  end

  def process_due_arrival!
    travel = user_ship.ship_travels
                      .where(is_paused: false, completed_at_tick: nil)
                      .where.not(arrival_tick: 0)
                      .where("arrival_tick <= ?", current_tick)
                      .order(arrival_tick: :desc, updated_at: :desc)
                      .first

    ShipTravelArrivalProcessor.new(travel: travel, current_tick: current_tick).call if travel
  rescue StandardError => error
    Rails.logger.error("event=lazy_arrival_failed ship_id=#{user_ship.id} error_class=#{error.class.name}")
    raise TravelLifecycle::Error.new('internal_failure','Arrival could not complete; the journey is retained for retry.')
  end

  private

  attr_reader :shard_user, :user_ship, :current_tick

  def ensure_player_location_from_ship
    return unless shard_user
    player_location = shard_user.current_location
    return player_location if player_location

    ship_location = user_ship.location || Location.find_by(name: user_ship.location_name)
    return unless ship_location

    shard_user.update_current_location!(ship_location)
    ship_location
  end
end
