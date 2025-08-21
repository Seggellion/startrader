# app/services/travel_service.rb
class TravelService
  DEFAULT_WINDOW_PERCENT = Setting.get("interdiction_window_percent")

  attr_reader :user_ship, :to_location

  def initialize(user_ship:, to_location:, interdict_window_percent: DEFAULT_WINDOW_PERCENT)
    @user_ship = user_ship
    @from_location = user_ship.location
    @to_location = to_location
    @interdict_window_percent = interdict_window_percent
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

    travel = ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: to_location,
      departure_tick: start_tick,
      arrival_tick: arrival_tick,
      total_duration_ticks: duration,
      interdict_window_percent: @interdict_window_percent
    )

    user_ship.update!(status: "in_transit")
    travel
  end
end
