module Api
    class ShipsController < ApplicationController
      # Renders public ship data in the specific legacy format
      def index
        @ships = Ship.all
        
        formatted_ships = @ships.map do |ship|
          {
            "shipname" => ship.name,
            # Grabs the first word (e.g., "Drake Interplanetary" -> "Drake")
            "manufacturer" => ship.company_name&.split(' ')&.first || "Unknown",
            "cargocapacity" => ship.scu.to_s,
            "requiresdocking" => ship.is_docking ? "true" : "false",
            "filename" => "#{ship.name&.gsub(' ', '_')}_Profile_#{ship.length.to_i}m.png",
            "keel" => ship.length.to_s,
            "msrp" => ship.msrp.to_s,
            "qfuel" => ship.fuel_quantum.to_s,
            "hp" => (ship.hp || 45).to_s, # Provide fallback if HP is not yet seeded
            "category" => ship.is_spaceship ? "ship" : "vehicle",
            "isactive" => "1"
          }
        end

        render json: formatted_ships
      end

def delete_all
      Ship.destroy_all
      redirect_to admin_ships_path, notice: 'All ships have been deleted successfully.'
    end

    end
end