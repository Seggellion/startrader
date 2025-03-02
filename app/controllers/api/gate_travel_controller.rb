module Api
    class GateTravelController < ApplicationController
        skip_before_action :verify_authenticity_token

      def gate_travel
        username = params[:username]
        user = User.find_by!(username: username)
  
        # Find the user's most recently updated ship
        user_ship = user.user_ships.order(updated_at: :desc).first
        raise StandardError, "No active ship found for user #{username}" unless user_ship
  
        # Find the current Jumpgate location
        current_location = Location.find_by!(name: user_ship.location_name)
        unless current_location.name.include?("Gateway")
          raise StandardError, "You are not at a valid Jumpgate location."
        end
  
        # Extract the star system name from the Jumpgate
        origin_star_system = current_location.star_system_name
  
        # Find the corresponding destination Jumpgate
        destination_location = Location.find_by("name LIKE ?", "%#{origin_star_system} Gateway%")
        unless destination_location
          raise StandardError, "No valid destination Jumpgate found."
        end
  
        # Update the UserShip location
        user_ship.update!(location_name: destination_location.name)
  
        render json: {
          status: "success",
          message: "You have traveled through the Jumpgate to #{destination_location.name}.",
          new_location: destination_location.name
        }
      rescue => e
        render json: { status: "error", message: e.message }, status: :unprocessable_entity
      end
    end
  end
  