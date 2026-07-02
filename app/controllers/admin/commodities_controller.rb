module Admin
    class CommoditiesController < ApplicationController
      before_action :set_commodity, only: [:update_category]
      def index
        @commodities = Commodity.all
      end
  
      def new
        @commodity = Commodity.new
      end
  
      def create
        @commodity = Commodity.new(commodity_params)



        @commodity.content.body = convert_h1_to_h2(@commodity.content.body.to_s)

        if @commodity.save
          redirect_to admin_commodities_path, notice: 'Commodity was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @commodity = Commodity.find_by_slug(params[:id])
      end
  
      def update
        @commodity = Commodity.find_by_slug(params[:id])
      
        # Update the commodity attributes first
        if @commodity.update(commodity_params)
          # If the commodity has content, process the ActionText content to replace <h1> with <h2>
          if @commodity.content.present?
            @commodity.content.body = convert_h1_to_h2(@commodity.content.body.to_s)
            @commodity.content.save # Ensure the changes to the RichText object are persisted
          end
      
          redirect_to edit_admin_commodity_path(@commodity), notice: 'Commodity was successfully updated.'
        else
          render :edit, alert: 'Failed to update the commodity.'
        end
      end
          

      def update_category

        if @commodity.update(commodity_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end
      def destroy
        @commodity = Commodity.find(params[:id])
        @commodity.destroy
        redirect_to admin_commodities_path, notice: 'Commodity was successfully deleted.'
      end

      def import_raw_json
        json_payload = params[:raw_json].presence || params[:json_data]

        if json_payload.present?
          imported_count = Admin::Data::CommoditiesImporter.import_raw_json!(json_payload)

          if imported_count > 0
            redirect_to admin_commodities_path, notice: "Successfully imported #{imported_count} commodities."
          else
            redirect_to admin_commodities_path, alert: "Import failed. Please verify the JSON format."
          end
        else
          redirect_to admin_commodities_path, alert: "No JSON data was provided."
        end
      end

      private
  
      def set_commodity
        
        @commodity = Commodity.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def commodity_params
        params.require(:commodity).permit(:title, :content, :category_id, :meta_description, :meta_keywords, :template, images: [], remove_images: []).merge(user_id: current_user.id)

      end
    end
  end
