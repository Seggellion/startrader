module Api
  class ShipsController < ApplicationController
    include SecretGuidAuth

    skip_before_action :verify_authenticity_token, only: [:dump_cargo, :deliver_ship]
    skip_before_action :authenticate_secret_guid!, only: [:index, :dump_cargo, :deliver_ship]

    # Renders public ship data in the specific legacy format
    def index
      @ships = Ship.where(is_spaceship:true, is_ground_vehicle:false)
        
        formatted_ships = @ships.map do |ship|
          {
            "shipname" => ship.name,
            # Grabs the first word (e.g., "Drake Interplanetary" -> "Drake")
            "manufacturer" => ship.company_name&.split(' ')&.first || "Unknown",
            "cargocapacity" => ship.scu.to_s,
            "requiresdocking" => ship.is_docking ? "true" : "false",
            "filename" => ship.ship_image_primary,
            "keel" => ship.length.to_s,
            "msrp" => ship.msrp.to_s,
            "qfuel" => ship.fuel_quantum.to_s,
            "hp" => (ship.hp || 45).to_s, # Provide fallback if HP is not yet seeded
            "category" => ship.is_spaceship ? "ship" : "vehicle",
            "isactive" => "1"
          }
        end

      render json: formatted_ships
    end

    def dump_cargo
      if params[:ship_guid].blank?
        render json: api_error_message('Missing ship_guid.'), status: :unprocessable_entity and return
      end

      if request.headers['X-Secret-Guid'].blank? && params[:secret_guid].blank?
        render json: api_error_message('Missing secret_guid.'), status: :unprocessable_entity and return
      end

      authenticate_secret_guid!
      return if performed?

      user_ship = UserShip.find_by(guid: params[:ship_guid])
      raise ActiveRecord::RecordNotFound, 'Ship not found.' unless user_ship

      result = UserShip.transaction do
        cargos = user_ship.user_ship_cargos.includes(:commodity).to_a
        message = build_jettison_message(cargos)

        cargos.each(&:destroy!)
        user_ship.recalculate_used_scu!

        api_success_message(message)
      end

      render json: result, status: :ok
    rescue StandardError => e
      render json: api_error_message(e.message), status: :unprocessable_entity
    end

    def deliver_ship
      if params[:ship_guid].blank?
        render json: api_error_message('Missing ship_guid.'), status: :unprocessable_entity and return
      end

      if params[:location].blank?
        render json: api_error_message('Missing location.'), status: :unprocessable_entity and return
      end

      if request.headers['X-Secret-Guid'].blank? && params[:secret_guid].blank?
        render json: api_error_message('Missing secret_guid.'), status: :unprocessable_entity and return
      end

      authenticate_secret_guid!
      return if performed?

      location = Location.find_by(name: params[:location])
      raise ActiveRecord::RecordNotFound, "Location not found: #{params[:location]}" unless location

      user_ship = UserShip.find_by(guid: params[:ship_guid])
      raise ActiveRecord::RecordNotFound, 'Ship not found.' unless user_ship

      result = UserShip.transaction do
        cargos = user_ship.user_ship_cargos.includes(:commodity).to_a
        message = build_delivery_message(location.name, cargos)

        user_ship.update!(location_name: location.name)
        cargos.each(&:destroy!)
        user_ship.recalculate_used_scu!

        api_success_message(message)
      end

      render json: result, status: :ok
    rescue StandardError => e
      render json: api_error_message(e.message), status: :unprocessable_entity
    end

    def delete_all
      Ship.destroy_all
      redirect_to admin_ships_path, notice: 'All ships have been deleted successfully.'
    end

    private

    def build_jettison_message(cargos)
      return 'no cargo to jettison' if cargos.empty?

      cargo_summaries = cargo_summaries(cargos)

      "jettisoned #{to_sentence(cargo_summaries)}"
    end

    def build_delivery_message(location_name, cargos)
      if cargos.empty?
        return "delivered ship to #{location_name} with no cargo to remove"
      end

      "delivered ship to #{location_name} and removed #{to_sentence(cargo_summaries(cargos))}"
    end

    def cargo_summaries(cargos)
      cargos
        .group_by { |cargo| cargo.commodity&.name.presence || cargo.commodity_name.presence || 'cargo' }
        .map do |commodity_name, cargo_items|
          "#{cargo_items.sum(&:scu)} scu of #{commodity_name.downcase}"
        end
    end

    def to_sentence(items)
      case items.length
      when 1
        items.first
      when 2
        items.join(' and ')
      else
        "#{items[0...-1].join(', ')}, and #{items.last}"
      end
    end

    def api_success_message(message)
      { Status: 'success', Message: message, ErrorText: '' }
    end

    def api_error_message(error_text)
      { Status: 'error', Message: '', ErrorText: error_text }
    end

    def secret_guid_auth_error_response
      api_error_message('Unauthorized')
    end
  end
end
