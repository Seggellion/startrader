# app/controllers/api/trades_controller.rb

module Api
  class TradesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def sell
      result = TradeService.sell(
        username: params[:username],
        wallet_balance: params[:wallet_balance].to_f,
        commodity_name: params[:commodity_name],
        scu: params[:scu].to_i
      )

      render json: result, status: :ok
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    # POST /api/buy
    def buy
      result = TradeService.buy(
        username: trade_params[:username],
        wallet_balance: trade_params[:wallet_balance].to_f,
        commodity_name: trade_params[:commodity_name],
        scu: trade_params[:scu].to_i
      )
      
      render json: result, status: :ok
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def status

      username = params.dig(:trade, :username) || params[:username] 

      wallet_balance = params[:wallet_balance]  # ✅ Get AEC balance from Twitch bot

      result = TradeService.status(username: username, wallet_balance: wallet_balance)

      render json: result, status: :ok
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    private

    def trade_params
      params.permit(:username, :wallet_balance, :commodity_name, :scu, :location)
    end
  end
end
