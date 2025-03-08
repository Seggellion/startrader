# app/services/travel_service.rb
class TravelService
  attr_reader :user_ship, :to_location

  def initialize(user_ship:, to_location:)    
    @user_ship = user_ship
    @from_location = user_ship.location
    @to_location = to_location
  end

  def call
    raise "Already in transit" if user_ship.active_travel.present?
    
    start_tick = Tick.current
    duration = TravelTimeCalculator.new(
      ship: user_ship.ship,
      from_location: @from_location,
      to_location: to_location,
      start_tick: start_tick
    ).calculate

    arrival_tick = start_tick + duration

    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: to_location,
      departure_tick: start_tick,
      arrival_tick: arrival_tick
    )

    # Do NOT update the location immediately; it will be updated upon arrival
    user_ship.update!(status: "in_transit")
  end
end
