module Admin
    class ShipTravelsController < ApplicationController
      def index
        @ship_travels = ShipTravel.all
      end
  
      def new
        @ship_travel = ShipTravel.new
      end
  
      def create
        @ship_travel = ShipTravel.new(ship_travel_params)


        if @ship_travel.save
          redirect_to admin_ship_travels_path, notice: 'ShipTravel was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @ship_travel = ShipTravel.find_by_id(params[:id])
      end
  
      def update
        @ship_travel = ShipTravel.find_by_id(params[:id])
      
        # Update the ship_travel attributes first
        if @ship_travel.update(ship_travel_params)
          # If the ship_travel has content, process the ActionText content to replace <h1> with <h2>

          redirect_to edit_admin_ship_travel_path(@ship_travel), notice: 'Commodity was successfully updated.'
        else
          render :edit, alert: 'Failed to update the ship_travel.'
        end
      end
          


      
      def delete_all
        ShipTravel.where(classification:"ship_travel").destroy_all
        redirect_to admin_ship_travels_path, notice: 'All ship_travels have been deleted successfully.'
      end
  
      def destroy
        @location = ShipTravel.find(params[:id])
        @location.destroy
        redirect_to admin_ship_travels_path, notice: 'ShipTravel was successfully deleted.'
      end
  
      private
  
      def set_ship_travel
        
        @ship_travel = Commodity.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def ship_travel_params
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
  