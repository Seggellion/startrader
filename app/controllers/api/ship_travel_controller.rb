
module Api
    class ShipTravelController < ApplicationController
      # Skip CSRF check for API-only endpoints
      skip_before_action :verify_authenticity_token
  
      # POST /api/travel
      def create
  
        user = User.first # Replace with the correct authentication or current user logic
        ship = Ship.find_by(slug: travel_params[:ship_slug])
        if ship.nil?
          render json: { error: "Ship with slug '#{travel_params[:ship_slug]}' not found." }, status: :not_found and return
        end
  
        user_ship = find_or_create_user_ship(user, ship)
  
        destination = Location.find_by(name: travel_params[:location])

        if destination.nil?
          render json: { error: "Location not found." }, status: :not_found and return
        end
  
        TravelService.new(user_ship: user_ship, to_location: destination).call
  
        render json: { status: 'travel_started', user_ship_id: user_ship.id }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
  
      # GET /api/location/:user_ship_id
      def location
        user_ship = UserShip.find_by(id: params[:user_ship_id])
        if user_ship.nil?
          render json: { error: "User ship not found." }, status: :not_found and return
        end
  
        active_travel = user_ship.active_travel
  
        if active_travel
          render json: {
            in_transit: true,
            from_location: active_travel.from_location.name,
            to_location: active_travel.to_location.name,
            departure_tick: active_travel.departure_tick,
            arrival_tick: active_travel.arrival_tick,
            current_tick: Tick.current
          }
        else
          render json: {
            in_transit: false,
            location: user_ship.location&.name || "Unknown"
          }
        end
      end
  
      private
  
      def travel_params
        params.require(:ship_travel).permit(:ship_slug, :location)
      end
  
      # Automatically creates a UserShip if not already present
      def find_or_create_user_ship(user, ship)
        
        user.user_ships.find_or_create_by(ship: ship) do |user_ship|
            user_ship.total_scu = ship.scu
            user_ship.used_scu = 0
          user_ship.location = Location.first # Default to a starting location, if needed
        end
      end
    end
  end
  