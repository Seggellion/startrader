module Admin
  class MoonsController < ApplicationController
    def index
      @moons = Location.where(classification: 'moon')
    end

    def new
      @commodity = Location.new
    end

    def create
      @moon = Location.new(moon_params)


      if @commodity.save
        redirect_to admin_moons_path, notice: 'Commodity was successfully created.'
      else
        render :new
      end
    end

    def edit
      @moon = Location.find_by_id(params[:id])
    end

    def update
      @moon = Location.find_by_id(params[:id])
    
      # Update the commodity attributes first
      if @moon.update(moon_params)
        # If the commodity has content, process the ActionText content to replace <h1> with <h2>

        redirect_to edit_admin_moon_path(@moon), notice: 'Commodity was successfully updated.'
      else
        render :edit, alert: 'Failed to update the commodity.'
      end
    end
        


    
    def delete_all
      Location.where(classification:"moon").destroy_all
      redirect_to admin_moons_path, notice: 'All moons have been deleted successfully.'
    end

    def destroy
      @location = Location.find(params[:id])
      @location.destroy
      redirect_to admin_moons_path, notice: 'Location was successfully deleted.'
    end

    private


    def moon_params
      params.require(:location).permit(
        :name,
        :nickname,
        :classification,
        :parent_name,
        :mass,
        :periapsis,
        :apoapsis,
        :code,
        :faction_name,
        :is_available,
        :is_available_live,
        :is_visible,
        :is_default_system,
        :is_affinity_influenceable,
        :is_habitation,
        :is_refinery,
        :is_cargo_center,
        :is_medical,
        :is_food,
        :is_shop_fps,
        :is_shop_vehicle,
        :is_refuel,
        :is_repair,
        :is_nqa,
        :is_player_owned,
        :is_auto_load,
        :has_loading_dock,
        :has_docking_port,
        :has_freight_elevator
      )
    end
    
  end
end
