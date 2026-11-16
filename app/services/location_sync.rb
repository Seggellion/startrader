# Single writer for named player/ship locations (M03; discovery F-03, F-20).
#
# Callers own authority decisions and locks (TravelLifecycle lock order:
# ship -> player -> GUID -> journey). This service only performs the writes,
# keeps ship and player changes in one transaction, and records which
# authority changed the player location (shard_users.location_source).
class LocationSync
  SOURCES = %w[client_status travel_departure travel_arrival repair delivery admin].freeze

  def self.player!(player, location, source:)
    check_source!(source)
    return if player.nil? || location.nil?

    player.update_current_location!(location, source: source)
  end

  def self.ship!(ship, location, source:, **attributes)
    check_source!(source)
    return if ship.nil? || location.nil?

    ship.update!(attributes.merge(location_name: location.name))
  end

  def self.both!(ship:, player:, location:, source:, **ship_attributes)
    ApplicationRecord.transaction do
      ship!(ship, location, source: source, **ship_attributes)
      player!(player, location, source: source)
    end
  end

  def self.check_source!(source)
    raise ArgumentError, "unknown location source #{source.inspect}" unless SOURCES.include?(source.to_s)
  end
  private_class_method :check_source!
end
