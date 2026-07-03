# app/controllers/api/trades_controller.rb

module Api
  class TradesController < BaseController
    skip_before_action :authenticate_secret_guid!, only: [:buy, :sell]

    def sell
      trade_params = params[:trade] || {}

      username = trade_params[:player_name]
      wallet_balance = trade_params[:wallet_balance]
      commodity_name = trade_params[:commodity_name]
      scu = trade_params[:scu]
      shard = trade_params[:shard_uuid]

      if username.blank? || shard.blank?
        render json: { status: 'error', message: 'Missing required parameters' }, status: :unprocessable_entity and return
      end

      if commodity_name.blank? && scu.blank?
        result = TradeService.list_sellable_commodities(username: username, shard: shard)
      elsif commodity_name.blank?
        render json: { status: 'error', message: 'Missing commodity name for sale.' }, status: :unprocessable_entity and return
      elsif scu.blank?
        render json: { status: 'error', message: 'Missing SCU amount for sale.' }, status: :unprocessable_entity and return
      else
        result = TradeService.sell(
          username: username,
          wallet_balance: wallet_balance,
          commodity_name: commodity_name,
          scu: scu,
          shard: shard
        )
      end

      render json: result, status: :ok
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def buy
      trade_params = params[:trade] || {}
      request_id = request.request_id

      username = trade_params[:player_name]
      wallet_balance = trade_params[:wallet_balance]
      commodity_name = trade_params[:commodity_name]
      scu = trade_params[:scu]
      shard = trade_params[:shard_uuid]
      ship_guid = trade_params[:ship_guid]
      ship_slug = trade_params[:ship_slug]
      payload_summary = trade_debug_payload_summary(trade_params)

      trade_debug_info('Api::TradesController#buy entry', request_id: request_id)
      trade_debug_info('Api::TradesController#buy payload', payload_summary.merge(request_id: request_id))

      if username.blank? || shard.blank?
        trade_debug_warn('Api::TradesController#buy branch missing required parameters', payload_summary.merge(request_id: request_id))
        render json: { status: 'error', message: 'Missing required parameters' }, status: :unprocessable_entity and return
      end

      if (commodity_name.blank? && scu.blank?) || blank_scu_listing_request?(trade_params)
        trade_debug_info('Api::TradesController#buy branch listing request', payload_summary.merge(request_id: request_id))
        result = TradeService.list_available_commodities(
          username: username,
          shard_uuid: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug,
          request_id: request_id
        )
      elsif commodity_name.blank?
        trade_debug_warn('Api::TradesController#buy branch missing commodity name', payload_summary.merge(request_id: request_id))
        render json: { status: 'error', message: 'Missing commodity name for purchase.' }, status: :unprocessable_entity and return
      elsif scu.blank?
        trade_debug_warn('Api::TradesController#buy branch missing SCU', payload_summary.merge(request_id: request_id))
        render json: { status: 'error', message: 'Missing SCU amount for purchase.' }, status: :unprocessable_entity and return
      else
        trade_debug_info('Api::TradesController#buy branch purchase request', payload_summary.merge(request_id: request_id))
        trade_debug_info('Api::TradesController#buy before TradeService.buy', payload_summary.merge(request_id: request_id))
        result = TradeService.buy(
          username: username,
          wallet_balance: wallet_balance,
          commodity_name: commodity_name,
          scu: scu,
          shard: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug,
          request_id: request_id
        )
      end

      trade_debug_info(
        'Api::TradesController#buy after service return',
        request_id: request_id,
        status: result[:status],
        message: result[:message]
      )

      render json: result, status: :ok
    rescue StandardError => e
      trade_debug_error(
        'Api::TradesController#buy failed',
        (defined?(payload_summary) && payload_summary ? payload_summary : {}).merge(
          request_id: (defined?(request_id) ? request_id : request.request_id),
          error_class: e.class.name,
          error_message: e.message,
          backtrace: e.backtrace&.join("\n")
        )
      )
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def status
      payload = normalized_status_payload

      Rails.logger.info(
        "[status] payload keys: ship_guid_present=#{payload[:ship_guid].present?} " \
        "ship_model_present=#{payload[:ship_model].present?} " \
        "shard_uuid_present=#{payload[:shard_uuid].present?} " \
        "player_guid_present=#{payload[:player_guid].present?} " \
        "player_name_present=#{payload[:player_name].present?} " \
        "location_present=#{payload[:location].present?} " \
        "wallet_balance_present=#{payload[:wallet_balance].present?}"
      )

      result = TradeService.status(
        ship_guid: payload[:ship_guid],
        ship_model: payload[:ship_model],
        shard_uuid: payload[:shard_uuid],
        player_guid: payload[:player_guid],
        player_name: payload[:player_name],
        location: payload[:location],
        wallet_balance: payload[:wallet_balance],
        username: payload[:username],
        shard: payload[:shard]
      )

      render json: result, status: :ok
    rescue TradeService::ValidationError => e
      render json: { status: 'error', message: e.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound => e
      render json: { status: 'error', message: e.message }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::TradesController#status] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    private

    def blank_scu_listing_request?(trade_params)
      (trade_params.key?(:scu) || trade_params.key?('scu')) && trade_params[:scu].blank?
    end

    def trade_debug_info(message, context = {})
      Rails.logger.info("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def trade_debug_warn(message, context = {})
      Rails.logger.warn("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def trade_debug_error(message, context = {})
      Rails.logger.error("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def trade_debug_context(context)
      context.compact.map { |key, value| "#{key}=#{value.inspect}" }.join(' ')
    end

    def trade_debug_payload_summary(trade_params)
      {
        player_name: trade_params[:player_name],
        commodity_name: trade_params[:commodity_name],
        scu: trade_params[:scu],
        shard_uuid: trade_params[:shard_uuid],
        shard_name: trade_params[:shard_name],
        ship_guid: trade_params[:ship_guid],
        ship_slug: trade_params[:ship_slug],
        wallet_balance_present: trade_params[:wallet_balance].present?
      }
    end

    def normalized_status_payload
      sources = status_payload_sources
      ship_guid = first_present_param(sources, :ship_guid)
      ship_model = first_present_param(sources, :ship_model)
      shard_uuid = first_present_param(sources, :shard_uuid)
      player_guid = first_present_param(sources, :player_guid)
      explicit_player_name = first_present_param(sources, :player_name)
      location = first_present_param(sources, :location)
      wallet_balance = first_present_param(sources, :wallet_balance)
      username = first_present_param(sources, :username)
      new_status_payload = ship_guid.present? || ship_model.present? || shard_uuid.present? ||
        player_guid.present? || explicit_player_name.present?

      {
        ship_guid: ship_guid,
        ship_model: ship_model,
        shard_uuid: shard_uuid,
        player_guid: player_guid,
        player_name: explicit_player_name || (username if new_status_payload),
        location: location,
        wallet_balance: wallet_balance,
        username: username,
        shard: shard_uuid || first_present_param(sources, :shard)
      }
    end

    def status_payload_sources
      sources = []

      if defined?(@json_payload) && @json_payload.present?
        sources << @json_payload
        sources << nested_param_source(@json_payload, :trade)
      end

      sources << nested_param_source(params, :trade)
      sources << params
      sources.compact
    end

    def nested_param_source(source, key)
      return unless source.respond_to?(:[])

      source[key] || source[key.to_s]
    end

    def first_present_param(sources, key)
      sources.each do |source|
        next if source.blank? || !source.respond_to?(:[])

        value = source[key] || source[key.to_s]
        return value if value.present?
      end

      nil
    end

    def trade_params
      params.permit(:username, :wallet_balance, :commodity_name, :scu, :location, :shard)
    end
  end
end
