# Decides whether a client status report may change saved locations.
#
# Decision Q1 (2026-11-16, narrowing v173):
# * While a ship has an UNFINISHED journey (active or interdicted), or a pending
#   travel request, the server journey is authoritative: the report may confirm
#   the saved location but cannot replace it (code stale_location, reason in_flight).
#   The same applies to the player when ANY of the player's ships is in flight.
# * After journeys finish, idle reports update locations again (fixes N-01).
# * Stale-origin guard (keeps v173's Ac3 protection): for STALE_ORIGIN_WINDOW_TICKS
#   after a journey completes, a report naming that journey's ORIGIN is ignored
#   (reason recent_origin), so a lagging client cannot drag a completed jump back.
# * Ships with any travel history keep v173's identity protection (Q4): status
#   cannot reassign them to another player, shard or ship model.
#
# The caller holds the selected ship and all affected player locks until the
# response is built (TravelLifecycle.with_status_ship).
class StatusLocationSync
  STALE_ORIGIN_WINDOW_TICKS = 40

  attr_reader :ship, :player, :reported_location

  def initialize(ship:, player:, reported_location:, tick: nil)
    @ship, @player, @reported_location = ship, player, reported_location
    @tick = tick
  end

  # In flight: the saved ship location is server-authoritative right now.
  def managed_ship?
    return @managed_ship if defined?(@managed_ship)

    @managed_ship = !!(persisted_ship && self.class.in_flight?(ship_scope))
  end

  def managed_player?
    return @managed_player if defined?(@managed_player)

    @managed_player = self.class.in_flight?(player_scope)
  end

  # Any journey or receipt ever: identity may not be reassigned by status (Q4).
  def travel_history?
    return @travel_history if defined?(@travel_history)

    @travel_history = !!(persisted_ship && self.class.travel_exists?(ship_scope))
  end

  def ship_location
    reported_location unless ignore_for_ship?
  end

  def player_location
    reported_location unless ignore_for_player?
  end

  def ignored_for
    return [] unless reported_location

    [].tap do |parts|
      parts << 'ship' if ignore_for_ship? && ship.location_name != reported_location.name
      parts << 'player' if ignore_for_player? && player.current_location_name != reported_location.name
    end
  end

  def payload
    return if ignored_for.empty?

    { status: 'ignored', code: 'stale_location', reason: reason,
      message: 'Saved travel locations were preserved. Refresh the client location from this response.',
      reported_location: reported_location.name, ignored_for: ignored_for }
  end

  def log(request_id:)
    return unless payload

    Rails.logger.warn("event=status_location_ignored request_id=#{request_id.inspect} " \
      "user_ship_id=#{ship&.id.inspect} shard_user_id=#{player.id} reason=#{reason} " \
      "reported_location_id=#{reported_location.id} ignored_for=#{ignored_for.join(',')}")
  end

  def self.in_flight?(ships)
    ids = ships.select(:id)
    ShipTravel.where(user_ship_id: ids, completed_at_tick: nil).exists? ||
      TravelRequestReceipt.where(user_ship_id: ids, outcome: 'pending').exists?
  end

  def self.travel_exists?(ships)
    ShipTravel.where(user_ship_id: ships.select(:id)).exists? ||
      TravelRequestReceipt.where(user_ship_id: ships.select(:id)).exists?
  end

  # Origins of journeys that completed within the guard window.
  def self.recent_origin_ids(ships, tick)
    TravelRequestReceipt.where(user_ship_id: ships.select(:id), outcome: 'completed')
      .where('completed_at_tick >= ?', tick - STALE_ORIGIN_WINDOW_TICKS)
      .pluck(:travel_snapshot).filter_map { |snapshot| snapshot&.dig('from_location_id') }
  end

  private

  def reason
    in_flight_ignore = (managed_ship? && ignored_for.include?('ship')) ||
      (managed_player? && ignored_for.include?('player'))
    in_flight_ignore ? 'in_flight' : 'recent_origin'
  end

  def ignore_for_ship?
    managed_ship? || recent_origin?(:ship)
  end

  def ignore_for_player?
    managed_player? || recent_origin?(:player)
  end

  def recent_origin?(target)
    @recent_origin ||= {}
    return @recent_origin[target] if @recent_origin.key?(target)

    scope = target == :ship ? (persisted_ship && ship_scope) : player_scope
    @recent_origin[target] = !!(reported_location && scope &&
      self.class.recent_origin_ids(scope, current_tick).include?(reported_location.id))
  end

  def current_tick
    @tick ||= Tick.order(:id).pick(:current_tick) || 0
  end

  def persisted_ship
    ship&.persisted?
  end

  def ship_scope
    @ship_scope ||= UserShip.where(id: ship.id)
  end

  def player_scope
    @player_scope ||= UserShip.where(shard_user_id: player.id)
  end
end
