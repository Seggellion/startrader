# Lock order: ship -> player -> GUID advisory lock -> journey -> receipt/event.
# Pause/resume/status paths use subsets and never acquire a GUID lock after a journey.
class TravelLifecycle
  MAX_TICK = 2_147_483_647
  class Error < TradeService::ValidationError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.with_ship(ship)
    UserShip.transaction do
      ship.lock!
      ship.shard_user&.lock!
      yield ship
    end
  end

  # Status locks a persisted ship before old/new players in ID order, and
  # retains those locks through response construction.
  def self.with_status_ship(ship, player)
    UserShip.transaction do
      ship.lock! if ship&.persisted?
      ids = [ship&.shard_user_id, player.id].compact.uniq.sort
      ShardUser.where(id: ids).order(:id).lock.load
      player.reload
      yield
    end
  end

  def self.deadline!(tick, duration)
    unless tick.is_a?(Integer) && tick >= 0 && duration.is_a?(Integer) && duration > 0 &&
        tick + duration <= MAX_TICK
      raise Error.new('invalid_state', 'Travel timing is invalid; review is required.')
    end
    tick + duration
  end

  def self.assert_free!(ship, tick)
    pending = ship.ship_travels.where(completed_at_tick:nil).order(:id).lock.to_a
    return if pending.empty?
    state = TravelState.new(pending.first, tick:tick)
    if pending.size > 1 || state.invalid?
      raise Error.new('invalid_state', 'Ship has inconsistent travel; review is required before departure.')
    elsif pending.first.is_paused?
      raise Error.new('interdicted', 'Ship is interdicted. Resolve the existing interdiction and resume its journey before departing.')
    else
      raise Error.new('in_transit', 'Ship is already in transit.')
    end
  end
end
