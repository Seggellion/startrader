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
      shard = trade_params[:shard_name]

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

      username = trade_params[:player_name]
      wallet_balance = trade_params[:wallet_balance]
      commodity_name = trade_params[:commodity_name]
      scu = trade_params[:scu]
      shard = trade_params[:shard_name]
      ship_guid = trade_params[:ship_guid]
      ship_slug = trade_params[:ship_slug]

      if username.blank? || shard.blank?
        render json: { status: 'error', message: 'Missing required parameters' }, status: :unprocessable_entity and return
      end

      if (commodity_name.blank? && scu.blank?) || blank_scu_listing_request?(trade_params)
        result = TradeService.list_available_commodities(
          username: username,
          shard: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug
        )
      elsif commodity_name.blank?
        render json: { status: 'error', message: 'Missing commodity name for purchase.' }, status: :unprocessable_entity and return
      elsif scu.blank?
        render json: { status: 'error', message: 'Missing SCU amount for purchase.' }, status: :unprocessable_entity and return
      else
        result = TradeService.buy(
          username: username,
          wallet_balance: wallet_balance,
          commodity_name: commodity_name,
          scu: scu,
          shard: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug
        )
      end

      render json: result, status: :ok
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def status
      payload = status_payload

      ship_guid = payload_value(payload, :ship_guid)
      broadcaster_id = payload_value(payload, :broadcaster_id)
      wallet_balance = payload_value(payload, :wallet_balance)
      username = payload.dig(:trade, :username) || payload.dig('trade', 'username') || payload_value(payload, :username)
      shard = payload_value(payload, :shard_uuid)

      result =
        if ship_guid.present? || broadcaster_id.present? || username.blank? || shard.blank?
          TradeService.status(
            ship_guid: ship_guid,
            broadcaster_id: broadcaster_id,
            wallet_balance: wallet_balance
          )
        else
          TradeService.status(username: username, wallet_balance: wallet_balance, shard: shard)
        end

      render json: result, status: :ok
    rescue TradeService::ValidationError => e
      render json: { status: 'error', message: e.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound => e
      render json: { status: 'error', message: e.message }, status: :not_found
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    private

    def blank_scu_listing_request?(trade_params)
      (trade_params.key?(:scu) || trade_params.key?('scu')) && trade_params[:scu].blank?
    end

    def status_payload
      @json_payload.presence || params
    end

    def payload_value(payload, key)
      payload[key] || payload[key.to_s]
    end

    def trade_params
      params.permit(:username, :wallet_balance, :commodity_name, :scu, :location, :shard)
    end
  end
end
