module Api
  class GateTravelController < BaseController
    def gate_travel
      ship_guid = params[:ship_guid].presence || parsed_json_value(:ship_guid).presence
      raise StandardError, "ship_guid is required" if ship_guid.blank?

      user_ship = UserShip.includes(:user, :ship, :shard, shard_user: :shard).find_by(guid: ship_guid)
      raise StandardError, "No user ship found for ship_guid #{ship_guid}" unless user_ship

      user = user_ship.user
      ship = user_ship.ship
      shard = resolved_shard_for(user_ship)

      raise StandardError, "No user found for ship_guid #{ship_guid}" unless user
      raise StandardError, "No ship found for ship_guid #{ship_guid}" unless ship
      raise StandardError, "No shard found for ship_guid #{ship_guid}" unless shard

      current_location = user_ship.location || Location.find_by(name: user_ship.location_name)
      raise StandardError, "Current location not found for ship_guid #{ship_guid}" unless current_location

      unless current_location.name.include?("Gateway")
        raise StandardError, "You are not at a valid Jumpgate location."
      end

      origin_star_system = current_location.star_system_name
      destination_location = Location
        .where("name LIKE ?", "%#{origin_star_system} Gateway%")
        .where.not(id: current_location.id)
        .first

      raise StandardError, "No valid destination Jumpgate found." unless destination_location

      user_ship.update!(location_name: destination_location.name)

      render json: {
        status: "success",
        message: "You have traveled through the Jumpgate to #{destination_location.name}.",
        new_location: destination_location.name
      }
    rescue => e
      render json: { status: "error", message: e.message }, status: :unprocessable_entity
    end

    private

    def resolved_shard_for(user_ship)
      user_ship.shard || user_ship.shard_user&.shard || Shard.find_by(name: user_ship.shard_name)
    end
  end
end
