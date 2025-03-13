module Admin
    class SpaceStationsController < ApplicationController
      before_action :set_location, only: [:update_category]
      def index
        @space_stations = Location.where(classification: 'space_station')
      end
  
      def new
        @space_station = Location.new
      end
  
      def create
        @space_station = Location.new(space_station_params)


        if @space_station.save
          redirect_to admin_space_stations_path, notice: 'Location was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @space_station = Location.find_by_id(params[:id])
      end
  
      def update
        @space_station = Location.find_by_id(params[:id])
      
        # Update the location attributes first
        if @space_station.update(station_params)

          redirect_to edit_admin_space_station_path(@space_station), notice: 'Space Station was successfully updated.'
        else
          render :edit, alert: 'Failed to update the location.'
        end
      end
          

      def update_category

        if @space_station.update(station_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

      def delete_all
        Location.where(classification:"space_station").destroy_all
        redirect_to admin_space_stations_path, notice: 'All space_station have been deleted successfully.'
      end

  
      def destroy
        @space_station = Location.find(params[:id])
        @space_station.destroy
        redirect_to admin_space_stations_path, notice: 'Location was successfully deleted.'
      end
  
      private
  
      def set_location
        
        @space_station = Location.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def station_params
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
  