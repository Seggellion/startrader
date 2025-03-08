module Admin
  class OutpostsController < ApplicationController
    def index
      @outposts = Location.where(classification: 'outpost')
    end

    def new
      @commodity = Location.new
    end

    def create
      @outpost = Location.new(outpost_params)


      if @commodity.save
        redirect_to admin_outposts_path, notice: 'Commodity was successfully created.'
      else
        render :new
      end
    end

    def edit
      @outpost = Location.find_by_id(params[:id])
    end

    def update
      @outpost = Location.find_by_id(params[:id])
    
      # Update the commodity attributes first
      if @outpost.update(outpost_params)
        # If the commodity has content, process the ActionText content to replace <h1> with <h2>

        redirect_to edit_admin_outpost_path(@outpost), notice: 'Commodity was successfully updated.'
      else
        render :edit, alert: 'Failed to update the commodity.'
      end
    end
        


    
    def delete_all
      Location.where(classification:"outpost").destroy_all
      redirect_to admin_outposts_path, notice: 'All outposts have been deleted successfully.'
    end

    def destroy
      @location = Location.find(params[:id])
      @location.destroy
      redirect_to admin_outposts_path, notice: 'Location was successfully deleted.'
    end

    private

    def set_commodity
      
      @commodity = Commodity.find(params[:id])
    end


    def outpost_params
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
