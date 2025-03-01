module Api
  class DistanceCalculatorController < ApplicationController
    skip_before_action :verify_authenticity_token

    # POST /api/distance_calculator
    def calculate
      # Parse input parameters from the JSON payload
      from_name = distance_params[:from]
      to_name = distance_params[:to]

      # Find locations by name
      from_location = Location.find_by(name: from_name)
      to_location = Location.find_by(name: to_name)

      # Handle invalid locations
      if from_location.nil? || to_location.nil?
        render json: { error: "Invalid locations provided. Ensure both 'from' and 'to' locations exist." }, status: :not_found
        return
      end

      # Calculate the distance using the current tick
      distance = from_location.distance_to(to_location, Tick.current)

      # Return the response in the desired format
      render json: {
        from: from_location.name,
        to: to_location.name,
        distance: distance,
        current_tick: Tick.current
      }
    end

    private

    def distance_params
      params.require(:distance).permit(:from, :to)
    end
  end
end
