module Api
  class GateTravelController < BaseController
    def gate_travel
      ship_guid = params[:ship_guid].presence || parsed_json_value(:ship_guid).presence
      result = GateTravelService.new(
        ship_guid: ship_guid,
        gateway_name: gateway_name_param,
        travel_guid: travel_guid_param
      ).call

      render json: {
        status: "success",
        message: "Gate travel initiated. Arrival pending.",
        travel_guid: result.travel.travel_guid,
        travel_time_seconds: result.travel_time_seconds,
        current_tick: result.travel.departure_tick,
        arrival_tick: result.travel.arrival_tick,
        time_remaining: result.travel.seconds_remaining(result.travel.departure_tick),
        origin_location: result.origin_location.name,
        origin_star_system: result.origin_star_system,
        arrival_location: result.arrival_location.name,
        arrival_star_system: result.target_star_system,
        new_location: result.arrival_location.name
      }
    rescue => e
      render json: { status: "error", message: e.message }, status: :unprocessable_entity
    end

    private

    def gateway_name_param
      first_present_param(
        :gateway_name,
        :destination_gateway,
        :destination,
        :to_gateway,
        :to_location
      )
    end

    def travel_guid_param
      first_present_param(:travel_guid)
    end

    def first_present_param(*keys)
      keys.each do |key|
        value = params[key].presence || parsed_json_value(key).presence
        return value if value.present?
      end

      nil
    end
  end
end
