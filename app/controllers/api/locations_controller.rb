# app/controllers/api/locations_controller.rb
module Api
  class LocationsController < ApplicationController
    include Rails.application.routes.url_helpers
    skip_before_action :verify_authenticity_token

    def index
      scope = Location.all
      scope = scope.where(star_system_name: params[:system])      if params[:system].present?
      scope = scope.where(classification: params[:location_type]) if params[:location_type].present?

      page = params[:page].to_i > 0 ? params[:page].to_i : 1
      per  = params[:per].to_i  > 0 ? [params[:per].to_i, 500].min : 100
      records = scope.order(:name).offset((page - 1) * per).limit(per)

      render json: {
        data: records.map { |loc| resource_object(loc) }
      }
    end

    def show
      loc = Location.find(params[:id])
      render json: { data: resource_object(loc) }
    end

    def create
      loc = Location.new(permitted_canonical_params.merge(legacy_to_canonical_params))
      if loc.save
        render json: { data: resource_object(loc) }, status: :created
      else
        render json: { errors: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      loc = Location.find(params[:id])
      if loc.update(permitted_canonical_params.merge(legacy_to_canonical_params))
        render json: { data: resource_object(loc) }
      else
        render json: { errors: loc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      Location.find(params[:id]).destroy
      head :no_content
    end

    private

    def resource_object(loc)
      {
        "id" => loc.id.to_s,
        "type" => "locations",
        "links" => {
          # If the legacy link must be WITHOUT /api, change to: location_url(loc)
          "self" => api_location_url(loc)
        },
        "attributes" => legacy_attributes(loc)
      }
    end

    def legacy_attributes(loc)
      {
        "name"               => loc.name,
        "location-type"      => legacy_location_type(loc),
        "parent"             => loc.parent_name,
        "ammenities-fuel"    => bool_or_null(loc.is_refuel),
        "ammenities-repair"  => bool_or_null(loc.is_repair),
        "ammenities-rearm"   => bool_or_null(loc.is_shop_fps),
        "trade-terminal"     => bool_or_null(loc.is_cargo_center),
        "system"             => loc.star_system_name,
        "mass"               => loc.mass,
        "apoapsis"           => loc.apoapsis,
        "periapsis"          => loc.periapsis
      }
    end

    def legacy_location_type(loc)
      loc.api_type.presence || loc.classification
    end

    def bool_or_null(v) = v ? true : nil

    def legacy_to_canonical_params
      lp = params.permit(
        :name, :location_type, :parent,
        :ammenities_fuel, :ammenities_repair, :ammenities_rearm,
        :trade_terminal, :system, :mass, :apoapsis, :periapsis
      )
      {}.tap do |h|
        h[:name]             = lp[:name]                       if lp.key?(:name)
        h[:classification]   = lp[:location_type]              if lp.key?(:location_type)
        h[:parent_name]      = lp[:parent]                     if lp.key?(:parent)
        h[:is_refuel]        = ActiveModel::Type::Boolean.new.cast(lp[:ammenities_fuel])   if lp.key?(:ammenities_fuel)
        h[:is_repair]        = ActiveModel::Type::Boolean.new.cast(lp[:ammenities_repair]) if lp.key?(:ammenities_repair)
        h[:is_shop_fps]      = ActiveModel::Type::Boolean.new.cast(lp[:ammenities_rearm])  if lp.key?(:ammenities_rearm)
        h[:is_cargo_center]  = ActiveModel::Type::Boolean.new.cast(lp[:trade_terminal])    if lp.key?(:trade_terminal)
        h[:star_system_name] = lp[:system]                     if lp.key?(:system)
        h[:mass]             = lp[:mass]                       if lp.key?(:mass)
        h[:apoapsis]         = lp[:apoapsis]                   if lp.key?(:apoapsis)
        h[:periapsis]        = lp[:periapsis]                  if lp.key?(:periapsis)
      end
    end

    def permitted_canonical_params
      params.permit(
        :name, :classification, :parent_name, :mass, :apoapsis, :periapsis, :star_system_name,
        :is_refuel, :is_repair, :is_shop_fps, :is_shop_vehicle, :is_cargo_center, :api_type
      )
    end
  end
end
