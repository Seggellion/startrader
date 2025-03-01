class ShipArrivalJob < ApplicationJob
  queue_as :default

  def perform
    current_tick = Tick.current

    # Find all ships scheduled to arrive at the current tick
    ShipTravel.where(arrival_tick: current_tick).find_each do |travel|
      # Update the UserShip to reflect arrival at the new location
      travel.user_ship.update!(
        location_name: travel.to_location.name,
        status: "docked"
      )

      # Clean up the completed ShipTravel record
      travel.destroy
    end
  end
end
