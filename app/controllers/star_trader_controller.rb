class StarTraderController < ApplicationController
  PER_PAGE = 50

  before_action :set_filter_options, only: %i[index market]

  def index
    set_star_trader_metadata
    load_dashboard
  end

  def market
    if turbo_frame_request?
      load_market
      render partial: "star_trader/market_results", locals: market_locals
    else
      set_star_trader_metadata
      load_dashboard
      render :index
    end
  end

  private

  def load_dashboard
    load_market
    @current_tick = Tick.instance
    @active_system = @filter_params[:star_system].presence || "Stanton"
    @tracked_locations_count = ProductionFacility.where.not(location_name: [nil, ""]).distinct.count(:location_name)
    @last_market_update_at = ProductionFacility.maximum(:updated_at)
    @overview = market_overview

    @selected_facility = @market_facilities.first
  end

  def load_market
    @market_result = MarketQuery.new(market_params).call
    @filter_params = @market_result.filters
    @market_facilities = @market_result.rows
  end

  def market_overview
    {
      best_buy: ProductionFacility.player_can_buy.where("#{ProductionFacility::PLAYER_BUY_PRICE_SQL} > 0").order(Arel.sql("#{ProductionFacility::PLAYER_BUY_PRICE_SQL} ASC")).includes(:commodity, :location).first,
      best_sell: ProductionFacility.player_can_sell.where("#{ProductionFacility::PLAYER_SELL_PRICE_SQL} > 0").order(Arel.sql("#{ProductionFacility::PLAYER_SELL_PRICE_SQL} DESC")).includes(:commodity, :location).first,
      volatile: ProductionFacility.where("price_sell_avg > 0 OR price_buy_avg > 0")
        .order(Arel.sql("ABS(COALESCE(local_sell_price, 0) - COALESCE(price_sell_avg, 0)) + ABS(COALESCE(local_buy_price, 0) - COALESCE(price_buy_avg, 0)) DESC"))
        .includes(:commodity, :location)
        .first,
      active_locations: @tracked_locations_count,
      commodities: Commodity.count,
      tick: @current_tick.current_tick
    }
  end

  def set_filter_options
    @star_systems = Location.where.not(star_system_name: [nil, ""]).distinct.order(:star_system_name).pluck(:star_system_name)
    @commodities = Commodity.order(:name).limit(500)
    @location_types = Location.where.not(classification: [nil, ""]).distinct.order(:classification).pluck(:classification)
  end

  def market_params
    params.slice(*MarketQuery::FILTER_KEYS)
  end

  def market_locals
    { market_result: @market_result }
  end

  def set_star_trader_metadata
    @meta_title = "Star Trader Command Center"
    @meta_description = "Live commodity market data, trade locations, and orbital positions for the StarBitizen Trade Network."
    @meta_keywords = "Star Trader, StarBitizen, commodities, trade routes, market prices, orbital simulator"
  end
end
