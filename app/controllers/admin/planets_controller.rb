module Admin
  class PlanetsController < ApplicationController
    before_action :set_planet, only: [:edit, :update, :destroy]

    def index
      @planets = Location.where(classification: 'planet')
    end

    def new
      @planet = Location.new
    end

    def create
      @planet = Location.new(planet_params)

      if @planet.save
        redirect_to admin_planets_path, notice: 'Planet was successfully created.'
      else
        render :new
      end
    end

    def edit
    end

    def update
      if @planet.update(planet_params)
        redirect_to edit_admin_planet_path(@planet), notice: 'Planet was successfully updated.'
      else
        render :edit, alert: 'Failed to update the planet.'
      end
    end

    def delete_all
      Location.where(classification: "planet").destroy_all
      redirect_to admin_planets_path, notice: 'All planets have been deleted successfully.'
    end

    def destroy
      @planet.destroy
      redirect_to admin_planets_path, notice: 'Location was successfully deleted.'
    end

    private

    def set_planet
      @planet = Location.find(params[:id])
    end

    def convert_h1_to_h2(html)
      html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
    end

    def planet_params
      params.require(:location).permit(
        :name, :nickname, :classification, :parent_name, :mass,
        :periapsis, :apoapsis, :code, :faction_name, :is_available,
        :is_available_live, :is_visible, :is_default_system,
        :is_affinity_influenceable, :is_habitation, :is_refinery,
        :is_cargo_center, :is_medical, :is_food, :is_shop_fps,
        :is_shop_vehicle, :is_refuel, :is_repair, :is_nqa,
        :is_player_owned, :is_auto_load, :has_loading_dock,
        :has_docking_port, :has_freight_elevator
      )
    end
  end
end