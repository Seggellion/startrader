class ShipTravelArrivalProcessor
  def initialize(travel:, current_tick: Tick.current, notify: true)
    @travel = travel
    @current_tick = current_tick
    @notify = notify
  end

  def call
    travel.with_lock do
      travel.reload
      return travel unless travel.due_for_arrival?(current_tick)

      travel.user_ship.update!(
        location_name: travel.to_location.name,
        status: arrival_status
      )

      RabbitmqSender.send_ship_report(travel) if notify
      travel.update!(completed_at_tick: current_tick)
    end

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
end
