
module Api
    class ShipTravelController < ApplicationController
      # Skip CSRF check for API-only endpoints
      skip_before_action :verify_authenticity_token
  
      # POST /api/travel
      def create
        user = find_or_create_user(travel_params[:username])

        
        # ✅ Find user case-insensitively
        shard = Shard.where("LOWER(name) = ?", shard).first

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
        
        user_ship = find_or_create_user_ship(user, ship, shard)
  
        if ShipTravel.exists?(user_ship_id: user_ship.id)
          return render json: { error: "Ship is already in transit." }, status: :unprocessable_entity
        end
        
        destination = Location.where("LOWER(name) = ?", travel_params[:location].downcase).first

        if destination.nil?
          render json: { error: "Location not found." }, status: :not_found and return
        end

        if user_ship.location.nil?          
          user_ship.update(location_name:destination.star_system_name)
        end
        
        if destination.star_system_name != user_ship.location.star_system_name
          render json: { error: "You cannot travel outside your current star system." }, status: :unprocessable_entity and return
        end
        
        TravelService.new(user_ship: user_ship, to_location: destination).call
  
        render json: { status: 'travel_started', user_ship_id: user_ship.id, current_tick: Tick.current, arrival_tick: ShipTravel.last.arrival_tick }
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


            # DELETE /api/cancel
            def destroy
              user = User.where("LOWER(username) = ?", params[:username].downcase.strip).first
            
              shard = params[:shard] 
              shard_user = user.shard_users.find_by(shard_name:shard)
              if user.nil?
                return render json: { error: "User not found." }, status: :not_found
              end
        
              user_ship = shard_user.user_ships.order(updated_at: :desc).first
        
              if user_ship.nil?
                return render json: { error: "User ship not found or does not belong to the specified user." }, status: :not_found
              end
        
              if user_ship.active_travel.nil?
                return render json: { error: "No active travel to cancel." }, status: :unprocessable_entity
              end
        
              user_ship.active_travel.destroy
              user_ship.update(status: "Floating aimlessly in space")
              render json: { status: "travel_cancelled", user_ship_id: user_ship.id }
            rescue StandardError => e
              render json: { error: e.message }, status: :unprocessable_entity
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
      def find_or_create_user_ship(user, ship, shard)
        
        user.user_ships.find_or_create_by(ship: ship) do |user_ship|
            user_ship.total_scu = ship.scu
            user_ship.used_scu = 0
            user_ship.shard_name = shard
          user_ship.location = Location.planets.find_by(name:"Hurston")
        end
      end
    end
  end
  