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
    @current_tick = Tick.instance
    @active_system = market_params[:star_system].presence || "Stanton"
    @tracked_locations_count = ProductionFacility.where.not(location_name: [nil, ""]).distinct.count(:location_name)
    @last_market_update_at = ProductionFacility.maximum(:updated_at)
    @overview = market_overview

    load_market
    @selected_facility = @market_facilities.first
  end

  def load_market
    @filter_params = market_params.to_h.symbolize_keys
    @market_page = [(@filter_params[:page].presence || 1).to_i, 1].max

    scoped = filtered_market_scope
    @total_count = scoped.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @market_facilities = scoped
      .includes(:commodity, :location)
      .offset((@market_page - 1) * PER_PAGE)
      .limit(PER_PAGE)
    @next_page = @market_page < @total_pages ? @market_page + 1 : nil
    @previous_page = @market_page > 1 ? @market_page - 1 : nil
  end

  def filtered_market_scope
    scope = ProductionFacility
      .left_joins(:commodity, :location)
      .where.not(commodity_name: [nil, ""])
      .where.not(location_name: [nil, ""])

    if @filter_params[:q].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@filter_params[:q])}%"
      scope = scope.where(
        "production_facilities.facility_name ILIKE :term OR production_facilities.location_name ILIKE :term OR production_facilities.commodity_name ILIKE :term OR locations.parent_name ILIKE :term OR locations.star_system_name ILIKE :term OR locations.planet_name ILIKE :term OR locations.moon_name ILIKE :term",
        term: term
      )
    end

    scope = scope.where(locations: { star_system_name: @filter_params[:star_system] }) if @filter_params[:star_system].present?
    scope = scope.where(commodity_name: Commodity.where(id: @filter_params[:commodity_id]).select(:name)) if @filter_params[:commodity_id].present?
    scope = scope.where(locations: { classification: @filter_params[:location_type] }) if @filter_params[:location_type].present?

    case @filter_params[:trade_mode]
    when "buy"
      scope = scope.where("COALESCE(production_facilities.local_sell_price, production_facilities.price_sell, 0) > 0")
    when "sell"
      scope = scope.where("COALESCE(production_facilities.local_buy_price, production_facilities.price_buy, 0) > 0")
    when "both"
      scope = scope.where("COALESCE(production_facilities.local_sell_price, production_facilities.price_sell, 0) > 0")
                   .where("COALESCE(production_facilities.local_buy_price, production_facilities.price_buy, 0) > 0")
    end

    scope.order(Arel.sql("#{sort_column} #{sort_direction} NULLS LAST"), id: :asc)
  end

  def sort_column
    {
      "location" => "production_facilities.location_name",
      "commodity" => "production_facilities.commodity_name",
      "buy_price" => "production_facilities.local_sell_price",
      "sell_price" => "production_facilities.local_buy_price",
      "inventory" => "production_facilities.inventory",
      "demand" => "production_facilities.scu_buy",
      "profit_margin" => "(COALESCE(production_facilities.local_buy_price, 0) - COALESCE(production_facilities.local_sell_price, 0))",
      "updated" => "production_facilities.updated_at"
    }.fetch(@filter_params[:sort].presence, "production_facilities.updated_at")
  end

  def sort_direction
    @filter_params[:direction] == "asc" ? "ASC" : "DESC"
  end

  def market_overview
    {
      best_buy: ProductionFacility.where("local_sell_price > 0").order(local_sell_price: :asc).includes(:commodity, :location).first,
      best_sell: ProductionFacility.where("local_buy_price > 0").order(local_buy_price: :desc).includes(:commodity, :location).first,
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
    params.permit(:q, :star_system, :commodity_id, :location_type, :trade_mode, :sort, :direction, :page)
  end

  def market_locals
    {
      market_facilities: @market_facilities,
      filter_params: @filter_params,
      total_count: @total_count,
      page: @market_page,
      total_pages: @total_pages,
      previous_page: @previous_page,
      next_page: @next_page
    }
  end

  def set_star_trader_metadata
    @meta_title = "Star Trader Command Center"
    @meta_description = "Live commodity market data, trade locations, and orbital positions for the StarBitizen Trade Network."
    @meta_keywords = "Star Trader, StarBitizen, commodities, trade routes, market prices, orbital simulator"
  end
end
