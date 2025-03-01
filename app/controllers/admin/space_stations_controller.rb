module Admin
    class SpaceStationsController < ApplicationController
      before_action :set_commodity, only: [:update_category]
      def index
        @space_stations = Location.where(classification: 'space_station')
      end
  
      def new
        @commodity = Location.new
      end
  
      def create
        @space_station = Location.new(space_station_params)


        if @commodity.save
          redirect_to admin_space_stations_path, notice: 'Commodity was successfully created.'
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

      def delete_all
        Location.where(classification:"space_station").destroy_all
        redirect_to admin_space_station_path, notice: 'All space_station have been deleted successfully.'
      end

  
      def destroy
        @commodity = Location.find(params[:id])
        @commodity.destroy
        redirect_to admin_space_stations_path, notice: 'Commodity was successfully deleted.'
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
  