# app/services/travel_time_calculator.rb
class TravelTimeCalculator
    def initialize(ship:, from_location:, to_location:, start_tick:)
      @ship = ship
      @from_location = from_location
      @to_location = to_location
      @start_tick = start_tick
    end
  
    def calculate
        
      distance = @from_location.distance_to(@to_location, @start_tick)
      base_speed = @ship.speed
      
      (distance / base_speed).ceil
    end
  end
  