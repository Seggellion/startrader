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

# app/controllers/admin/ships_controller.rb

def import_starbitizen
  begin
    # Parse the pasted string, and use Array.wrap to guarantee 
    # it's an array, even if the user pastes a single JSON object.
    raw_parsed_json = JSON.parse(params[:json_data])
    json_payload = Array.wrap(raw_parsed_json)
    
    updated_count = 0
    not_found_ships = []

    json_payload.each do |data|
      # Case-insensitive lookup to prevent mismatches
      ship = Ship.where('lower(name) = ?', data["shipname"].to_s.downcase).first

      if ship
        # Update the record with mapped JSON values
        ship.update(
          scu: data["cargocapacity"],
          length: data["keel"],
          msrp: data["msrp"],
          hp: data["hp"],
          is_docking: data["requiresdocking"].to_s.downcase == "true",
          fuel_quantum: data["qfuel"],
          qnt_fuel_capacity: data["qfuel"]
        )
        updated_count += 1
      else
        not_found_ships << data["shipname"]
      end
    end

    message = "Successfully updated #{updated_count} ships."
    message += " Could not find: #{not_found_ships.join(', ')}." if not_found_ships.any?
    
    redirect_to admin_ships_path, notice: message

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
