module Admin
  class DataController < ApplicationController
 
    def import_ships
        if Admin::Data::ShipsImporter.import_all!
          flash[:notice] = "One ship imported successfully!"
        else
          flash[:alert] = "Failed to import ships."
        end
        redirect_to admin_vehicles_path
      end
  
      def import_commodities
        if Admin::Data::CommoditiesImporter.import_all!
          flash[:notice] = "One commodity imported successfully!"
        else
          flash[:alert] = "Failed to import ships."
        end
        redirect_to admin_commodities_path
      end
  
      def populate_facilities
        if Admin::Data::FacilitiesPopulator.import_all!
          flash[:notice] = "One Facility populated successfully!"
        else
          flash[:alert] = "Failed to import ships."
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
        if Admin::Data::StarSystemsImporter.import_all!
          flash[:notice] = "All Star Systems imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_star_systems_path
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
        if Admin::Data::StationsImporter.import_all!
          flash[:notice] = "All Stations imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
        end
        redirect_to admin_space_stations_path
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
        if Admin::Data::TerminalsImporter.import_all!
       # if Admin::Data::TerminalsImporter.import_single!
          flash[:notice] = "One terminal imported successfully!"
        else
          flash[:alert] = "Failed to import locations."
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
