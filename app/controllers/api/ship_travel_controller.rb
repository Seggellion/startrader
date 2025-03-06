
module Api
    class ShipTravelController < ApplicationController
      # Skip CSRF check for API-only endpoints
      skip_before_action :verify_authenticity_token
  
      # POST /api/travel
      def create
        user = find_or_create_user(travel_params[:username])
        
        # ✅ Find ship if slug is provided, otherwise use most recent UserShip
        ship = Ship.find_by(slug: travel_params[:ship_slug]) if travel_params[:ship_slug].present?
      
        # ✅ If no ship is found, use the user's most recently updated UserShip
        unless ship
          user_ship = user.user_ships.order(updated_at: :desc).first
      
          if user_ship
            ship = user_ship.ship  # ✅ Assign the most recent ship
          else
            render json: { error: "No ship found for user '#{user.username}'." }, status: :not_found and return
          end
        end
      
        user_ship = find_or_create_user_ship(user, ship)
  
        if ShipTravel.exists?(user_ship_id: user_ship.id)
          return render json: { error: "Ship is already in transit." }, status: :unprocessable_entity
        end

        destination = Location.find_by(name: travel_params[:location])

        if destination.nil?
          render json: { error: "Location not found." }, status: :not_found and return
        end
  
        if destination.star_system_name != user_ship.location.star_system_name
          render json: { error: "You cannot travel outside your current star system." }, status: :unprocessable_entity and return
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
        params.require(:ship_travel).permit(:ship_slug, :location, :username)
      end
  

          # Find or create a user by username with "provider: twitch"
          def find_or_create_user(username)
            normalized_username = username.downcase.strip
          
            # ✅ Find user case-insensitively
            user = User.where("LOWER(username) = ?", normalized_username).first
          
            # ✅ Create user only if not found
            unless user
              user = User.create!(
                username: normalized_username,
                uid: SecureRandom.hex(10),
                twitch_id: SecureRandom.hex(10),
                user_type: "player",
                provider: "twitch"
              )
            end
          
            user
          end
          

      # Automatically creates a UserShip if not already present
      def find_or_create_user_ship(user, ship)
        
        user.user_ships.find_or_create_by(ship: ship) do |user_ship|
            user_ship.total_scu = ship.scu
            user_ship.used_scu = 0
          user_ship.location = Location.planets.find_by(name:"Hurston")
        end
      end
    end
  end
  