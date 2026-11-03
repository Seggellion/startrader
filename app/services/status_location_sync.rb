# A status report has no causal version or proof of movement. Once server travel
# exists, it may confirm the saved location, but cannot replace it. The caller
# holds the selected ship and all affected player locks until the response is built.
class StatusLocationSync
  attr_reader :ship, :player, :reported_location

  def initialize(ship:, player:, reported_location:)
    @ship, @player, @reported_location = ship, player, reported_location
  end

  def managed_ship?
    return @managed_ship if defined?(@managed_ship)

    @managed_ship = !!(ship&.persisted? && self.class.travel_exists?(UserShip.where(id: ship.id)))
  end

  def managed_player?
    return @managed_player if defined?(@managed_player)

    @managed_player = self.class.travel_exists?(UserShip.where(shard_user_id: player.id))
  end

  def ship_location
    reported_location unless managed_ship?
  end

  def player_location
    reported_location unless managed_player?
  end

  def ignored_for
    return [] unless reported_location

    [].tap do |parts|
      parts << 'ship' if managed_ship? && ship.location_name != reported_location.name
      parts << 'player' if managed_player? && player.current_location_name != reported_location.name
    end
  end

  def payload
    return if ignored_for.empty?

    { status: 'ignored', code: 'stale_location',
      message: 'Saved travel locations were preserved. Refresh the client location from this response.',
      reported_location: reported_location.name, ignored_for: ignored_for }
  end

  def log(request_id:)
    return unless payload

    Rails.logger.warn("event=status_location_ignored request_id=#{request_id.inspect} " \
      "user_ship_id=#{ship&.id.inspect} shard_user_id=#{player.id} " \
      "reported_location_id=#{reported_location.id} ignored_for=#{ignored_for.join(',')}")
  end

  def self.travel_exists?(ships)
    ShipTravel.where(user_ship_id: ships.select(:id)).exists? ||
      TravelRequestReceipt.where(user_ship_id: ships.select(:id)).exists?
  end
end
