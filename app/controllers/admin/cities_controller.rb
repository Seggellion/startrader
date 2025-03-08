module Admin
  class CitiesController < ApplicationController
    def index
      @cities = Location.where(classification: 'city')
    end

    def new
      @commodity = Location.new
    end

    def create
      @city = Location.new(city_params)


      if @commodity.save
        redirect_to admin_cities_path, notice: 'Commodity was successfully created.'
      else
        render :new
      end
    end

    def edit
      @city = Location.find_by_id(params[:id])
    end

    def update
      @city = Location.find_by_id(params[:id])
    
      # Update the commodity attributes first
      if @city.update(city_params)
        # If the commodity has content, process the ActionText content to replace <h1> with <h2>

        redirect_to edit_admin_city_path(@city), notice: 'Commodity was successfully updated.'
      else
        render :edit, alert: 'Failed to update the commodity.'
      end
    end
        


    
    def delete_all
      city_ids = Location.where(classification: "city").pluck(:id)
      ShipTravel.where(from_location_id: city_ids).or(ShipTravel.where(to_location_id: city_ids)).destroy_all

      Location.where(classification:"city").destroy_all
      redirect_to admin_cities_path, notice: 'All cities have been deleted successfully.'
    end

    def destroy
      @location = Location.find(params[:id])
      @location.destroy
      redirect_to admin_cities_path, notice: 'Location was successfully deleted.'
    end

    private

    def set_commodity
      
      @commodity = Commodity.find(params[:id])
    end


    def city_params
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
