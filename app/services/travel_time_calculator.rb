require_relative '../../lib/travel_timing'

class TravelTimeCalculator
  # Keep the ship keyword for callers; ordinary speed is uniform.
  def initialize(ship:, from_location:, to_location:, start_tick:)
    @from_location = from_location
    @to_location = to_location
    @start_tick = start_tick
  end

  def calculate
    TravelTiming.duration_ticks(@from_location.distance_to(@to_location, @start_tick))
  end
end
