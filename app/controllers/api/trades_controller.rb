# app/controllers/api/trades_controller.rb

module Api
  class TradesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def sell

      trade_params = params[:trade] || {}
    
      username = trade_params[:player_name]
      wallet_balance = trade_params[:wallet_balance]
      commodity_name = trade_params[:commodity_name]
      scu = trade_params[:scu]
      shard = trade_params[:shard_name]

      result = TradeService.sell(
        username: username,
        wallet_balance: wallet_balance,
        commodity_name: commodity_name,
        scu: scu,
        shard: shard
      )

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


      if username.blank? || shard.blank?
        render json: { status: 'error', message: 'Missing required parameters' }, status: :unprocessable_entity and return
      end
    
      if commodity_name.blank?
        # ✅ List all commodities available for purchase at the user's location
        result = TradeService.list_available_commodities(username: username)
      else
        # ✅ Proceed with buying the commodity
        result = TradeService.buy(
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
    

    def status

      username = params.dig(:trade, :username) || params[:username]       
      shard = params[:shard_uuid] 
      wallet_balance = params[:wallet_balance]  # ✅ Get AEC balance from Twitch bot

      result = TradeService.status(username: username, wallet_balance: wallet_balance, shard: shard)

      render json: result, status: :ok
    rescue StandardError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def self.list_available_commodities(username:)
      
  user = User.where("LOWER(username) = ?", username.downcase).first!
  user_ship = user.user_ships.order(updated_at: :desc).first

  if user_ship.nil?
    raise ShipNotFoundError, "No ship found for user '#{username}'."
  end

  location_name = user_ship.location_name
  location = Location.where("name ILIKE ?", "%#{location_name}%").first!
  commodities = ProductionFacility.where("? ILIKE '%' || location_name || '%'", location.name)
                                   .where("local_buy_price > 0")  # ✅ Only show buyable commodities
                                   .includes(:commodity)
                                   .map do |facility|
    {
      commodity_name: facility.commodity.name,
      price: facility.local_buy_price
    }
  end

  if commodities.empty?
    return { status: 'error', message: "No commodities available for purchase at #{location_name}." }
  end

  {
    status: 'success',
    location: location_name,
    commodities: commodities
  }
end


    private

    def trade_params
      params.permit(:username, :wallet_balance, :commodity_name, :scu, :location, :shard)
    end
  end
end
