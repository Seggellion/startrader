# app/controllers/api/locations_controller.rb
module Api
  class LocationsController < ApplicationController
    include Rails.application.routes.url_helpers
    skip_before_action :verify_authenticity_token

    # GET /api/locations
    # Returns an array of resource objects (no {data: ...} wrapper)
    def index
      scope = Location.all
      scope = scope.where(star_system_name: params[:system])      if params[:system].present?
      scope = scope.where(classification: params[:location_type]) if params[:location_type].present?

      # simple paging: ?page=1&per=100
      page = params[:page].to_i > 0 ? params[:page].to_i : 1
      per  = params[:per].to_i  > 0 ? [params[:per].to_i, 500].min : 100
      records = scope.order(:name).offset((page - 1) * per).limit(per)

      render json: records.map { |loc| resource_object(loc) }
    end

    # GET /api/locations/:id
    # Returns a single resource object (no {data: ...} wrapper)
    def show
      loc = Location.find(params[:id])
      render json: resource_object(loc)
    end

    # POST /api/locations
    def create
      loc = Location.new(permitted_canonical_params.merge(legacy_to_canonical_params))
      if loc.save
        render json: resource_object(loc), status: :created
      else
        render json: { error: "Validation failed", details: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/locations/:id
    def update
      loc = Location.find(params[:id])
      if loc.update(permitted_canonical_params.merge(legacy_to_canonical_params))
        render json: resource_object(loc)
      else
        render json: { error: "Validation failed", details: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/locations/:id
    def destroy
      Location.find(params[:id]).destroy
      head :no_content
    end

    private

    # -------- Resource object (JSON:API-like) --------
    def resource_object(loc)
      {
        "id" => loc.id.to_s,
        "type" => "locations",
        "links" => {
          "self" => api_location_url(loc) # e.g. https://your.host/api/locations/54
        },
        "attributes" => legacy_attributes(loc)
      }
    end

    # Dasherized legacy attributes + nulls instead of false
    def legacy_attributes(loc)
      {
        "name"               => loc.name,
        "location-type"      => legacy_location_type(loc),
        "parent"             => loc.parent_name,
        "ammenities-fuel"    => bool_or_null(loc.is_refuel),
        "ammenities-repair"  => bool_or_null(loc.is_repair),
        "ammenities-rearm"   => bool_or_null(amenities_rearm?(loc)),
        "trade-terminal"     => bool_or_null(trade_terminal?(loc)),
        "system"             => loc.star_system_name,
        "mass"               => loc.mass,
        "apoapsis"           => loc.apoapsis,
        "periapsis"          => loc.periapsis
      }
    end

    # ---- Mapping helpers (tweak here to match the old API exactly) ----

    # Your legacy sample shows "location-type": "1".
    # If your app stored numeric codes previously, map them here.
    # Default is to return what you have (classification or api_type).
    def legacy_location_type(loc)
      # Example mapping; replace with your historic codes if needed:
      # CODES = { "star_system" => "1", "planet" => "2", "moon" => "3",
      #           "space_station" => "4", "outpost" => "5", "city" => "6", "poi" => "7" }.freeze
      # CODES[loc.classification] || loc.api_type || loc.classification

      loc.api_type.presence || loc.classification # <= non-breaking default
    end

    def amenities_rearm?(loc)
      # Old API had rearm null for many entries; only return true if you *know* it’s available.
      # Map to an ammo/weapon shop flag if that's what the old API implied:
      loc.is_shop_fps
    end

    def trade_terminal?(loc)
      # Reasonable proxy; change if your legacy API used a different signal (e.g., actual terminals table)
      loc.is_cargo_center
    end

    # Render true as true, false/nil as null.
    def bool_or_null(v)
      v ? true : nil
    end

    # -------- Writes: accept both legacy and canonical keys --------
    def legacy_to_canonical_params
      lp = params.permit(
        :name, :location_type, :parent,
        :ammenities_fuel, :ammenities_repair, :ammenities_rearm,
        :trade_terminal, :system, :mass, :apoapsis, :periapsis
      )
      {}.tap do |h|
        h[:name]             = lp[:name]                          if lp.key?(:name)
        h[:classification]   = lp[:location_type]                 if lp.key?(:location_type)
        h[:parent_name]      = lp[:parent]                        if lp.key?(:parent)
        h[:is_refuel]        = to_bool(lp[:ammenities_fuel])      if lp.key?(:ammenities_fuel)
        h[:is_repair]        = to_bool(lp[:ammenities_repair])    if lp.key?(:ammenities_repair)
        h[:is_shop_fps]      = to_bool(lp[:ammenities_rearm])     if lp.key?(:ammenities_rearm)
        h[:is_cargo_center]  = to_bool(lp[:trade_terminal])       if lp.key?(:trade_terminal)
        h[:star_system_name] = lp[:system]                        if lp.key?(:system)
        h[:mass]             = lp[:mass]                          if lp.key?(:mass)
        h[:apoapsis]         = lp[:apoapsis]                      if lp.key?(:apoapsis)
        h[:periapsis]        = lp[:periapsis]                     if lp.key?(:periapsis)
      end
    end

    def permitted_canonical_params
      params.permit(
        :name, :classification, :parent_name, :mass, :apoapsis, :periapsis, :star_system_name,
        :is_refuel, :is_repair, :is_shop_fps, :is_shop_vehicle, :is_cargo_center, :api_type
      )
    end

    def to_bool(v)
      ActiveModel::Type::Boolean.new.cast(v)
    end
  end
end
