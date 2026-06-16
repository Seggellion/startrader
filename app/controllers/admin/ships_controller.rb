# app/controllers/admin/ships_controller.rb
module Admin
  class ShipsController < ApplicationController
    before_action :set_ship, only: [:edit, :update, :destroy, :update_category]

    def index
      @ships = Ship.order(created_at: :desc)
    end

    def new
      @ship = Ship.new
    end

    def create
      @ship = Ship.new(ship_params.merge(user_id: current_user.id))

      if @ship.save
        redirect_to edit_admin_ship_path(@ship), notice: 'ship was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def import_starbitizen
      begin
        result = Admin::Data::StarbitizenShipImporter.import_raw_json!(params[:json_data])
        flash_key = result.failed_count.positive? ? :alert : :notice

        redirect_to admin_ships_path, flash_key => result.message
      rescue JSON::ParserError
        redirect_to admin_ships_path, alert: "Invalid JSON format. Please ensure you pasted valid JSON."
      rescue => e
        redirect_to admin_ships_path, alert: "An error occurred: #{e.message}"
      end
    end

    def update
      if @ship.update(ship_params)
        redirect_to edit_admin_ship_path(@ship), notice: 'Ship was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def update_category
      if @ship.update(ship_params.slice(:category_id))
        render json: { success: true }
      else
        render json: { success: false }, status: :unprocessable_entity
      end
    end

    def delete_all
      Ship.destroy_all
      redirect_to admin_ships_path, notice: 'All ships have been deleted successfully.'
    end

    def destroy
      @ship.destroy
      redirect_to admin_ships_path, notice: 'Ship was successfully deleted.'
    end

    private

    def set_ship
      
      @ship = Ship.find(params[:id])
    end


    def ship_params
      params.require(:ship).permit(
        :model, :category_id, :slug, :speed
      )
    end
  end
end
