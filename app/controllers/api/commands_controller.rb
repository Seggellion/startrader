module Api
      class CommandsController < BaseController
        # POST /api/v1/commands/travel
        def travel
          user = find_user
          destination_name = command_params[:destination]
          destination = Location.find_by(name: destination_name)
  
          if destination.nil?
            return render json: { error: "Destination '#{destination_name}' not found" }, status: :not_found
          end
  
          # Simple approach: instantly move the user to the destination
          # In a real system, you might handle travel time, in-transit states, etc.
          user.update(location_id: destination.id)
  
          render json: {
            message: "User #{user.username} traveling to #{destination.name}",
            user_location: user.location_id
          }, status: :ok
        end
  
        # POST /api/v1/commands/buy
        def buy
          user = find_user
          commodity_name = command_params[:commodity]
          quantity       = command_params[:quantity].to_i
  
          commodity = Commodity.find_by(name: commodity_name)
          if commodity.nil?
            return render json: { error: "Commodity '#{commodity_name}' not found" }, status: :not_found
          end
  
          # Check user’s current location
          unless user.location&.trade_port?
            return render json: { error: "Cannot buy at this location" }, status: :forbidden
          end
  
          # TODO: Implement cargo capacity checks (UserShip, UserShipCargo)
          # e.g. user_ship = user.user_ships.first
          # Check user_ship.available_cargo_space >= quantity
          # Deduct credits if needed, etc.
  
          # For demonstration, we just respond with a success message
          render json: {
            message: "Purchased #{quantity} SCU of #{commodity.name} at #{user.location.name}"
          }, status: :ok
        end
  
        # POST /api/v1/commands/sell
        def sell
          user = find_user
          commodity_name = command_params[:commodity]
          quantity       = command_params[:quantity].to_i
  
          commodity = Commodity.find_by(name: commodity_name)
          if commodity.nil?
            return render json: { error: "Commodity '#{commodity_name}' not found" }, status: :not_found
          end
  
          # Check user’s current location
          unless user.location&.trade_port?
            return render json: { error: "Cannot sell at this location" }, status: :forbidden
          end
  
          # TODO: Implement cargo checks to see if the user actually has the commodity in cargo
          # Remove quantity from user_ship_cargo, credit user, etc.
  
          render json: {
            message: "Sold #{quantity} SCU of #{commodity.name} at #{user.location.name}"
          }, status: :ok
        end
  
        private
  
        def command_params
          # If you’re using @json_payload from parse_json_request:
          #   @json_payload might look like { "user_twitch_id": "...", "destination": "area-18", ... }
          # If you’re passing standard params, adapt as needed
          params.permit(:user_twitch_id, :destination, :commodity, :quantity)
        end
  
        def find_user
          # E.g., find user by Twitch ID
          user = User.find_by(user_twitch_id: command_params[:user_twitch_id])
          if user.nil?
            render json: { error: 'User not found' }, status: :not_found and return
          end
          user
        end
      end
  end
  