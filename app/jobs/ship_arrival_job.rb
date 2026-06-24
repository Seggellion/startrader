class ShipArrivalJob < ApplicationJob
  queue_as :default

  def perform
    current_tick = Tick.current
  
    # Find all ships scheduled to arrive at or before the current tick.
    ShipTravel.where("arrival_tick <= ?", current_tick)
              .where.not(arrival_tick: 0)
              .where(is_paused: false, completed_at_tick: nil)
              .find_each do |travel|
      ShipTravelArrivalProcessor.new(travel: travel, current_tick: current_tick).call
    end
  end
  
end
