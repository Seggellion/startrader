module Admin
    class VehiclesController < ApplicationController
      before_action :set_vehicle, only: [:update_category]
      def index
        @vehicles = Ship.all
      end
  
      def new
        @vehicle = Location.new
      end
  
      def create
        @vehicle = Location.new(vehicle_params)


        if @vehicle.save
          redirect_to admin_vehicles_path, notice: 'Commodity was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @vehicle = Commodity.find_by_slug(params[:id])
      end
  
      def update
        @vehicle = Commodity.find_by_slug(params[:id])
      
        # Update the vehicle attributes first
        if @vehicle.update(vehicle_params)
          # If the vehicle has content, process the ActionText content to replace <h1> with <h2>
          if @vehicle.content.present?
            @vehicle.content.body = convert_h1_to_h2(@vehicle.content.body.to_s)
            @vehicle.content.save # Ensure the changes to the RichText object are persisted
          end
      
          redirect_to edit_admin_vehicle_path(@vehicle), notice: 'Commodity was successfully updated.'
        else
          render :edit, alert: 'Failed to update the vehicle.'
        end
      end
          

      def update_category

        if @vehicle.update(vehicle_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

      def delete_all
        Ship.destroy_all
        redirect_to admin_vehicles_path, notice: 'All ships have been deleted successfully.'
      end
  
      def destroy
        @location = Ship.find(params[:id])
        @location.destroy
        redirect_to admin_vehicles_path, notice: 'Location was successfully deleted.'
      end
  
      private
  
      def set_vehicle
        
        @vehicle = Commodity.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def vehicle_params
        params.require(:vehicle).permit(:title, :content, :category_id, :meta_description, :meta_keywords, :template, images: [], remove_images: []).merge(user_id: current_user.id)

      end
    end
  end
  