module Admin
  class DataController < ApplicationController
 



def import_ships
      json_payload = params[:json_data]
      
      if json_payload.present?
        imported_count = Admin::Data::ShipsImporter.import_raw_json!(json_payload)
        
        if imported_count > 0
          redirect_to admin_ships_path, notice: "Successfully imported #{imported_count} ships."
        else
          redirect_to admin_ships_path, alert: "Import failed. Please verify the JSON format."
        end
      else
        redirect_to admin_ships_path, alert: "No JSON data was provided."
      end
    end
  
      def import_commodities
        imported_count = Admin::Data::CommoditiesImporter.import_all!

        if imported_count > 0
          flash[:notice] = "Successfully imported #{imported_count} commodities."
        else
          flash[:alert] = "Failed to import commodities."
        end

        redirect_to admin_commodities_path
      end
  
      def populate_facilities
        imported_count = Admin::Data::FacilitiesPopulator.import_all!

        if imported_count > 0
          flash[:notice] = "Successfully imported #{imported_count} facilities."
        else
          flash[:alert] = "Failed to import facilities."
        end

        redirect_to admin_production_facilities_path
      end
  
      def import_outposts
        if Admin::Data::OutpostsImporter.import_all!
          flash[:notice] = "All Outposts imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_outposts_path
      end

      
      def import_star_systems
        json_payload = params[:json_data].presence || params[:raw_json]

        if json_payload.present?
          imported_count = Admin::Data::StarSystemsImporter.import_raw_json!(json_payload)

          if imported_count > 0
            redirect_to admin_star_systems_path, notice: "Successfully imported #{imported_count} star systems."
          else
            redirect_to admin_star_systems_path, alert: "Import failed. Please verify the JSON format."
          end
        else
          redirect_to admin_star_systems_path, alert: "No JSON data was provided."
        end
      end

      def import_cities
        if Admin::Data::CitiesImporter.import_all!
          flash[:notice] = "All Cities imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_cities_path
      end

    def import_stations
      json_payload = params[:json_data]
      
      if json_payload.present?
        imported_count = Admin::Data::StationsImporter.import_raw_json!(json_payload)
        
        if imported_count > 0
          redirect_to admin_space_stations_path, notice: "Successfully imported #{imported_count} space stations."
        else
          redirect_to admin_space_stations_path, alert: "Import failed. Please verify the JSON format."
        end
      else
        redirect_to admin_space_stations_path, alert: "No JSON data was provided."
      end
    end
      
      def import_moons
        if Admin::Data::MoonsImporter.import_all!
          flash[:notice] = "All Moons imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_moons_path
      end

      def import_planets
        if Admin::Data::PlanetsImporter.import_all!
          flash[:notice] = "One Planet imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_planets_path
      end

      def import_locations
        if Admin::Data::LocationsImporter.import_all!
          flash[:notice] = "One location imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_planets_path
      end

      def import_terminals
        import_result = Admin::Data::TerminalsImporter.import_all!
        imported_count = import_result.to_i

        if imported_count > 0
          flash[:notice] = import_result.respond_to?(:summary) ? import_result.summary : "Successfully imported #{imported_count} terminals."
        else
          flash[:alert] = "Failed to import terminals."
        end

        redirect_to admin_terminals_path
      end
  
      private
  
      # Fetch JSON data from the API
      def fetch_api_data(url)
        response = Net::HTTP.get(URI(url))
        JSON.parse(response)
      rescue => e
        Rails.logger.error "Failed to fetch data: #{e.message}"
        nil
      end


  end
end
