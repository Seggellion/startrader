class ShipTravelArrivalProcessor
  def initialize(travel:, current_tick: Tick.current, notify: true)
    @travel = travel
    @current_tick = current_tick
    @notify = notify
  end

  def call
    return travel if travel.destroyed?

    travel.with_lock do
      travel.reload
      return travel unless travel.due_for_arrival?(current_tick)

      travel.user_ship.update!(
        location_name: travel.to_location.name,
        status: arrival_status
      )
      update_player_location_if_travel_origin_matches!

      RabbitmqSender.send_ship_report(travel) if notify
      travel.cleanup_after_arrival!(current_tick)
    end

    travel
  rescue ActiveRecord::RecordNotFound
    travel
  end

  private

  attr_reader :travel, :current_tick, :notify

  def arrival_status
    case travel.to_location.classification
    when "space_station" then "docked"
    when "planet", "moon" then "in orbit"
    when "city", "outpost" then "landed"
    else "floating"
    end
  end

  def update_player_location_if_travel_origin_matches!
    shard_user = travel.user_ship.shard_user
    return unless shard_user

    current_location = shard_user.current_location
    if current_location.nil? || current_location.id == travel.from_location_id
      shard_user.update_current_location!(travel.to_location)
    end
  end
end
