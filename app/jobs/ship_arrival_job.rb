class ShipArrivalJob < ApplicationJob
  queue_as :default

  def perform
    current_tick = Tick.current
  
    # Find all ships scheduled to arrive at or before the current tick
    ShipTravel.where("arrival_tick <= ?", current_tick).find_each do |travel|
      # Determine the appropriate status based on the location classification
      status = case travel.to_location.classification
               when "space_station" then "docked"
               when "planet", "moon" then "in orbit"
               when "city", "outpost" then "landed"
               else "floating" # Fallback status in case of unexpected classification
               end
  
      # Update the UserShip to reflect arrival at the new location
      travel.user_ship.update!(
        location_name: travel.to_location.name,
        status: status
      )
      
      TwitchNotificationService.notify_arrival(travel.user.username, travel.to_location.name)

      # Clean up the completed ShipTravel record
      travel.destroy
    end
  end
  
end
