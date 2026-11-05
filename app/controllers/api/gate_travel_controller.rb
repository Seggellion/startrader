module Api
  class GateTravelController < BaseController
    def gate_travel
      environment = RabbitmqConnection.normalize(first_present_param(:rabbitmq))
      if environment && !RabbitmqConnection.valid_environment?(environment)
        return render json:{status:'error', code:'invalid_rabbitmq',
          message:'rabbitmq must be one of: prod, dev.'}, status: :unprocessable_entity
      end
      result = GateTravelService.new(
        ship_guid: first_present_param(:ship_guid),
        gateway_name: gateway_name_param,
        travel_guid: first_present_param(:travel_guid),
        rabbitmq_environment: environment,
        expected_origin_location: first_present_param(:expected_origin_location, :from_location, :origin_location),
        expected_destination_location: first_present_param(:expected_destination_location)
      ).call

      TravelLifecycle.with_ship(result.user_ship) do
        tick = Tick.current
        receipt = TravelRequestReceipt.find_by!(travel_guid:result.travel.travel_guid)
        journey = ShipTravel.find_by(travel_guid:result.travel.travel_guid) || ShipTravel.instantiate(receipt.travel_snapshot)
        outcome = journey.is_paused? ? 'paused' : receipt.outcome
        finalized = %w[completed cancelled destroyed].include?(outcome)
        trace = "event=gate_request_#{result.travel.request_replayed ? 'replayed' : 'accepted'} " \
          "request_id=#{request.request_id.inspect} user_ship_id=#{result.user_ship.id} receipt_id=#{receipt.id} " \
          "from_location_id=#{result.origin_location.id} to_location_id=#{result.arrival_location.id} " \
          "rabbitmq=#{journey.rabbitmq_environment} routing_source=#{result.routing_source} lifecycle_status=#{outcome} " \
          "gateway_selected=#{gateway_name_param.present?} request_guid_supplied=#{first_present_param(:travel_guid).present?}"
        ActiveRecord.after_all_transactions_commit { Rails.logger.info(trace) }
        render json: {
          status: "success",
          message: outcome == 'completed' ? 'Gate travel already completed. Saved arrival returned.' :
            (outcome == 'pending' ? 'Gate travel initiated. Arrival pending.' : "Gate travel is #{outcome}."),
          travel_guid: result.travel.travel_guid,
          travel_time_seconds: result.travel_time_seconds,
          departure_tick: journey.departure_tick,
          current_tick: tick,
          arrival_tick: journey.arrival_tick,
          time_remaining: finalized ? 0 : journey.seconds_remaining(tick),
          rabbitmq: journey.rabbitmq_environment,
          rabbitmq_source: result.routing_source,
          origin_location: result.origin_location.name,
          origin_star_system: result.origin_star_system,
          arrival_location: result.arrival_location.name,
          arrival_star_system: result.target_star_system,
          current_location: result.user_ship.location_name,
          player_location: result.user_ship.shard_user&.current_location_name,
          current_star_system: result.user_ship.location&.star_system_name,
          ship_status: result.user_ship.status,
          request_replayed: !!result.travel.request_replayed,
          lifecycle_status: outcome,
          new_location: result.arrival_location.name
        }
      end
    rescue GateTravelService::IntentError => e
      Rails.logger.warn("event=gate_request_blocked request_id=#{request.request_id.inspect} code=#{e.code} user_ship_id=#{e.state[:user_ship_id]}")
      render json:{status:'error',message:e.message,code:e.code}.merge(e.state),status: :unprocessable_entity
    rescue TravelLifecycle::Error => e
      Rails.logger.warn("event=gate_request_blocked request_id=#{request.request_id.inspect} code=#{e.code}")
      render json: {status:'error',message:e.message,code:e.code},status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      render json: {status:'error',message:'Travel request conflicts with an existing journey.',code:'request_conflict'},status: :unprocessable_entity
    rescue => e
      expected = e.instance_of?(StandardError)
      Rails.logger.error("event=gate_request_failed request_id=#{request.request_id.inspect} error_class=#{e.class.name}") unless expected
      render json: {status:'error',message:expected ? e.message : 'Travel could not start; retry or request review.',
        code:expected ? 'invalid_request' : 'internal_failure'},status: :unprocessable_entity
    end

    private

    def gateway_name_param
      first_present_param(:gateway_name, :destination_gateway, :destination, :to_gateway, :to_location)
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
