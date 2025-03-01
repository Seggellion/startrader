module Admin
    class StarSystemsController < ApplicationController
      before_action :set_star_system, only: [:update_category]
      def index
        @star_systems = Location.where(classification: 'star_system')
      end
  
      def new
        @star_system = Location.new
      end
  
      def create
        @star_system = Location.new(star_system_params)


        if @star_system.save
          redirect_to admin_star_systems_path, notice: 'Star System was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @star = Location.find_by_id(params[:id])
      end

      def update
        @star = Location.find_by_id(params[:id])
      
        # Update the commodity attributes first
        if @star.update(star_system_params)
          # If the commodity has content, process the ActionText content to replace <h1> with <h2>

          redirect_to edit_admin_star_system_path(@star), notice: 'Star was successfully updated.'
        else
          render :edit, alert: 'Failed to update the commodity.'
        end
      end
          

      def update_category

        if @star_system.update(star_system_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

      def delete_all
        Location.where(classification:"star_system").destroy_all
        redirect_to admin_star_systems_path, notice: 'All planets have been deleted successfully.'
      end
  
      def destroy
        @location = Location.find(params[:id])
        @location.destroy
        redirect_to admin_star_systems_path, notice: 'Location was successfully deleted.'
      end
  
      private
  
      def set_star_system
        
        @star_system = Commodity.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      
      def star_system_params
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
  