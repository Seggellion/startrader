# app/services/travel_service.rb
class TravelService
  DEFAULT_WINDOW_PERCENT = 15

  attr_reader :user_ship, :to_location, :travel_guid

  def initialize(user_ship:, to_location:, travel_guid:, from_location: nil, interdict_window_percent: nil, start_tick: nil)
    @user_ship = user_ship
    @from_location = from_location || user_ship.location
    @to_location = to_location
    @travel_guid = travel_guid
    @interdict_window_percent = interdict_window_percent || Setting.get("interdiction_window_percent") || DEFAULT_WINDOW_PERCENT
    @start_tick = start_tick
  end

  def call
    raise ArgumentError, "travel_guid is required." if travel_guid.blank?
    raise "Already in transit" if ShipAvailability.new(shard_user: user_ship.shard_user, user_ship: user_ship).in_transit?
    raise "Current location not found for ship." if @from_location.nil?
    raise "Ship is already at that location." if @from_location&.id == to_location.id

    stored_location = user_ship.location || Location.find_by(name: user_ship.location_name)
    if stored_location.present? && stored_location.id != @from_location.id
      raise "Ship is at #{stored_location.name}, not #{@from_location.name}."
    end

    start_tick = @start_tick || Tick.current
    
    # 1. Get the raw calculated duration
    calculated_duration = TravelTimeCalculator.new(
      ship: user_ship.ship,
      from_location: @from_location,
      to_location: to_location,
      start_tick: start_tick
    ).calculate

    # 2. Enforce the minimum 2-tick travel time constraint
    duration = [calculated_duration, 2].max

    arrival_tick = start_tick + duration

    # 3. Create the travel record with the validated duration
    travel = ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: to_location,
      travel_guid: travel_guid,
      departure_tick: start_tick,
      arrival_tick: arrival_tick,
      total_duration_ticks: duration,
      interdict_window_percent: @interdict_window_percent
    )

    user_ship.update!(location_name: @from_location.name, status: "in_transit")
    user_ship.shard_user&.update_current_location!(@from_location)
    travel
  end
end
