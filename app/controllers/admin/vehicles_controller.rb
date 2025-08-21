# app/controllers/admin/vehicles_controller.rb
module Admin
  class VehiclesController < ApplicationController
    before_action :set_vehicle, only: [:edit, :update, :destroy, :update_category]

    def index
      @vehicles = Ship.order(created_at: :desc)
    end

    def new
      @vehicle = Ship.new
    end

    def create
      @vehicle = Ship.new(vehicle_params.merge(user_id: current_user.id))

      if @vehicle.save
        redirect_to edit_admin_vehicle_path(@vehicle), notice: 'Vehicle was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @vehicle.update(vehicle_params)
        if @vehicle.content.present?
          @vehicle.content.body = convert_h1_to_h2(@vehicle.content.body.to_s)
          @vehicle.content.save
        end
        redirect_to edit_admin_vehicle_path(@vehicle), notice: 'Ship was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def update_category
      if @vehicle.update(vehicle_params.slice(:category_id))
        render json: { success: true }
      else
        render json: { success: false }, status: :unprocessable_entity
      end
    end

    def delete_all
      Ship.destroy_all
      redirect_to admin_vehicles_path, notice: 'All vehicles have been deleted successfully.'
    end

    def destroy
      @vehicle.destroy
      redirect_to admin_vehicles_path, notice: 'Ship was successfully deleted.'
    end

    private

    def set_vehicle
      
      @vehicle = Ship.find(params[:id])
    end

    def convert_h1_to_h2(html)
      html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
    end

    def vehicle_params
      params.require(:vehicle).permit(
        :model, :content, :category_id, :slug
      )
    end
  end
end
