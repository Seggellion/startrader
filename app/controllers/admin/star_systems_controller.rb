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
        @star_system = Commodity.find_by_slug(params[:id])
      end
  
      def update
        @star_system = Commodity.find_by_slug(params[:id])
      
        # Update the star_system attributes first
        if @star_system.update(star_system_params)
          # If the star_system has content, process the ActionText content to replace <h1> with <h2>
          if @star_system.content.present?
            @star_system.content.body = convert_h1_to_h2(@star_system.content.body.to_s)
            @star_system.content.save # Ensure the changes to the RichText object are persisted
          end
      
          redirect_to edit_admin_star_system_path(@star_system), notice: 'Commodity was successfully updated.'
        else
          render :edit, alert: 'Failed to update the star_system.'
        end
      end
          

      def update_category

        if @star_system.update(star_system_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
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
        params.require(:star_system).permit(:title, :content, :category_id, :meta_description, :meta_keywords, :template, images: [], remove_images: []).merge(user_id: current_user.id)

      end
    end
  end
  