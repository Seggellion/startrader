module Admin
    class ProductionFacilitiesController < ApplicationController
      before_action :set_production_facility, only: [:update_category]
      def index
        @production_facilities = ProductionFacility.order(Arel.sql("CASE WHEN price_buy > 0 THEN 0 ELSE 1 END"), :facility_name)
      end
  
      def new
        @production_facility = Location.new
      end
  
      def create
        @production_facility = ProductionFacility.new(production_facility_params)


        if @production_facility.save
          redirect_to admin_production_facilities_path, notice: 'ProductionFacility was successfully created.'
        else
          render :new
        end
      end
  
      def edit
      
        @production_facility = ProductionFacility.find_by_id(params[:id])
      end
  
      def update
        @production_facility = ProductionFacility.find_by_id(params[:id])
      
        # Update the production_facility attributes first
        if @production_facility.update(production_facility_params)
          # If the production_facility has content, process the ActionText content to replace <h1> with <h2>
      
          redirect_to edit_admin_production_facility_path(@production_facility), notice: 'ProductionFacility was successfully updated.'
        else
          render :edit, alert: 'Failed to update the production_facility.'
        end
      end
          

      def update_category

        if @production_facility.update(production_facility_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

      def delete_all
        ProductionFacility.destroy_all
        redirect_to admin_production_facilities_path, notice: 'All facilities have been deleted successfully.'
      end
  
      def destroy
        @production_facility = ProductionFacility.find(params[:id])
        @production_facility.destroy
        redirect_to admin_production_facilities_path, notice: 'ProductionFacility was successfully deleted.'
      end
  
      private
  
      def set_production_facility
        
        @production_facility = ProductionFacility.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def production_facility_params
        params.require(:production_facility).permit(
          :facility_name, :commodity_id, :location_name, :production_rate, 
          :consumption_rate, :inventory, :max_inventory, :local_buy_price, 
          :local_sell_price
        )
      end
    end
  end
  