# app/controllers/api/locations_controller.rb
module Api
  class LocationsController < ApplicationController
    skip_before_action :verify_authenticity_token

    # GET /api/locations
    def index
      # Optional filters: ?system=Stanton&location_type=city&visible=true
      scope = Location.all
      scope = scope.where(star_system_name: params[:system])            if params[:system].present?
      scope = scope.where(classification: params[:location_type])       if params[:location_type].present?
      scope = scope.where(is_visible: ActiveModel::Type::Boolean.new.cast(params[:visible])) if params.key?(:visible)

      # Basic pagination: ?page=1&per=100
      page = params[:page].to_i > 0 ? params[:page].to_i : 1
      per  = params[:per].to_i  > 0 ? [params[:per].to_i, 500].min : 100
      records = scope.order(:name).offset((page - 1) * per).limit(per)

      render json: {
        data: records.map { |loc| serialize_legacy(loc) },
        pagination: {
          page: page,
          per: per,
          total: scope.count
        }
      }
    end

    # GET /api/locations/:id
    def show
      loc = Location.find(params[:id])
      render json: serialize_legacy(loc)
    end

    # POST /api/locations
    # Accepts either legacy keys or canonical DB column names.
    def create
      loc = Location.new(permitted_canonical_params.merge(legacy_to_canonical_params))
      if loc.save
        render json: serialize_legacy(loc), status: :created
      else
        render json: { error: "Validation failed", details: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/locations/:id
    def update
      loc = Location.find(params[:id])
      if loc.update(permitted_canonical_params.merge(legacy_to_canonical_params))
        render json: serialize_legacy(loc)
      else
        render json: { error: "Validation failed", details: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/locations/:id
    def destroy
      loc = Location.find(params[:id])
      loc.destroy
      head :no_content
    end

    private

    # === Legacy → Canonical mapping for writes ===
    # Allows clients to keep sending old keys.
    def legacy_to_canonical_params
      lp = params.permit(
        :name, :location_type, :parent, :ammenities_fuel, :ammenities_repair, :ammenities_rearm,
        :trade_terminal, :system, :mass, :apoapsis, :periapsis
      )

      {}.tap do |h|
        h[:name]             = lp[:name]                                if lp.key?(:name)
        h[:classification]   = lp[:location_type]                       if lp.key?(:location_type)
        h[:parent_name]      = lp[:parent]                              if lp.key?(:parent)
        h[:is_refuel]        = truthy(lp[:ammenities_fuel])             if lp.key?(:ammenities_fuel)
        h[:is_repair]        = truthy(lp[:ammenities_repair])           if lp.key?(:ammenities_repair)
        # Rearm & trade terminal are derived in reads; but if legacy sends them, accept & do a best guess:
        h[:is_shop_fps]      = truthy(lp[:ammenities_rearm])            if lp.key?(:ammenities_rearm)
        h[:is_cargo_center]  = truthy(lp[:trade_terminal])              if lp.key?(:trade_terminal)
        h[:star_system_name] = lp[:system]                               if lp.key?(:system)
        h[:mass]             = lp[:mass]                                 if lp.key?(:mass)
        h[:apoapsis]         = lp[:apoapsis]                             if lp.key?(:apoapsis)
        h[:periapsis]        = lp[:periapsis]                            if lp.key?(:periapsis)
      end
    end

    # Accept canonical DB columns for writes too.
    def permitted_canonical_params
      params.permit(
        :name, :classification, :parent_name, :mass, :apoapsis, :periapsis, :star_system_name,
        :is_refuel, :is_repair, :is_shop_fps, :is_shop_vehicle, :is_cargo_center
      )
    end

    def truthy(v)
      ActiveModel::Type::Boolean.new.cast(v)
    end

    # === Canonical → Legacy serializer (for reads) ===
    # Keeps the exact legacy keys used by your existing clients.
    def serialize_legacy(loc)
      {
        name:               loc.name,
        location_type:      loc.classification,
        parent:             loc.parent_name,
        ammenities_fuel:    loc.is_refuel,
        ammenities_repair:  loc.is_repair,
        # Rearm (legacy): best practical proxy is "ammo/weapon shop available".
        # We map to is_shop_fps (weapons/ammo). Adjust here if you prefer a different flag.
        ammenities_rearm:   !!loc.is_shop_fps,
        # Trade terminal (legacy): good proxy is cargo/trade capability.
        # We map to is_cargo_center. If you later add real terminals, update this logic.
        trade_terminal:     !!loc.is_cargo_center,
        system:             loc.star_system_name,
        mass:               loc.mass,
        apoapsis:           loc.apoapsis,
        periapsis:          loc.periapsis
      }
    end
  end
end
