# app/services/admin/data/locations_importer.rb

module Admin
  module Data
    class StationsImporter
      LOCATION_URLS = [
        "https://api.uexcorp.space/2.0/space_stations"
      ].freeze

      # 🚦 Import all locations from all endpoints
      def self.import_all!
        imported_count = 0

        LOCATION_URLS.each do |url|
          data = fetch_api_data(url)
          next unless data&.any?

          data['data'].each do |location_data|
            if import_location(location_data)
              imported_count += 1
            end
          end
        end

        Rails.logger.info "Successfully imported #{imported_count} locations."
        imported_count
      rescue => e
        Rails.logger.error "Failed to import all locations: #{e.message}"
        0
      end


      # 📥 Import locations from a raw JSON string
      def self.import_raw_json!(json_string)
        imported_count = 0
        data = JSON.parse(json_string)

        return 0 unless data&.any?

        # Safely extract the array, whether it's wrapped in a 'data' key or pasted directly as an array
        locations_array = data['data'] || data

        locations_array.each do |location_data|
          if import_location(location_data)
            imported_count += 1
          end
        end

        Rails.logger.info "Successfully imported #{imported_count} locations via raw JSON."
        imported_count
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (StationsImporter): #{e.message}"
        0
      rescue => e
        Rails.logger.error "Failed to import raw JSON locations: #{e.message}"
        0
      end

      # 🚦 Import a single location for testing
      def self.import_single!
        LOCATION_URLS.each do |url|
          data = fetch_api_data(url)
          next unless data&.any?

          location_data = data['data'] ? data['data'].first : data.first
          return true if import_location(location_data)
        end

        false
      end

      # 🧠 Handle the import logic for a single location
      def self.import_location(location_data)
        classification = "space_station"
        parent_name = determine_parent_name(location_data)

        location = Location.find_or_initialize_by(name: location_data['name'])
        location.assign_attributes(
          nickname: location_data['nickname'],
          classification: classification,
          code: location_data['code'],
          api_id: location_data['id'],
          parent_name: parent_name,
          id_star_system: location_data['id_star_system'],
          id_planet: location_data['id_planet'],
          id_orbit: location_data['id_orbit'],
          id_moon: location_data['id_moon'],
          id_space_station: location_data['id_space_station'],
          id_outpost: location_data['id_outpost'],
          id_poi: location_data['id_poi'],
          id_city: location_data['id_city'],
          id_faction: location_data['id_faction'],
          id_company: location_data['id_company'],
          api_type: location_data['type'],
          mass: 500,
          periapsis: 200,
          apoapsis: 200,

          # Boolean flags
          is_available: location_data['is_available'].to_i == 1,
          is_available_live: location_data['is_available_live'].to_i == 1,
          is_visible: location_data['is_visible'].to_i == 1,
          is_default_system: location_data['is_default_system'].to_i == 1,
          is_affinity_influenceable: location_data['is_affinity_influenceable'].to_i == 1,
          is_habitation: location_data['has_habitation'].to_i == 1,
          is_refinery: location_data['has_refinery'].to_i == 1,
          is_cargo_center: location_data['has_cargo_center'].to_i == 1,
          is_medical: location_data['has_clinic'].to_i == 1,
          is_food: location_data['has_food'].to_i == 1,
          is_shop_fps: location_data['is_shop_fps'].to_i == 1,
          is_shop_vehicle: location_data['is_shop_vehicle'].to_i == 1,
          is_refuel: location_data['has_refuel'].to_i == 1,
          is_repair: location_data['has_repair'].to_i == 1,
          is_nqa: location_data['is_nqa'].to_i == 1,
          is_player_owned: location_data['is_player_owned'].to_i == 1,
          is_auto_load: location_data['is_auto_load'].to_i == 1,
          has_loading_dock: location_data['has_loading_dock'].to_i == 1,
          has_docking_port: location_data['has_docking_port'].to_i == 1,
          has_freight_elevator: location_data['has_freight_elevator'].to_i == 1,
          has_trade_terminal:location_data['has_trade_terminal'].to_i == 1,
          # Name mappings
          star_system_name: location_data['star_system_name'],
          planet_name: location_data['planet_name'],
          orbit_name: location_data['orbit_name'],
          moon_name: location_data['moon_name'],
          space_station_name: location_data['name'],
          outpost_name: location_data['outpost_name'],
          city_name: location_data['city_name'],
          faction_name: location_data['faction_name'],
          company_name: location_data['company_name'],

          max_container_size: location_data['max_container_size'].to_i,
          date_added: location_data['date_added'].to_i,
          date_modified: location_data['date_modified'].to_i
        )
        
        location.save!
      rescue => e
        Rails.logger.error "Failed to import location #{location_data['name']}: #{e.message}"
        false
      end

      # 🌐 Fetch JSON data from the API
      def self.fetch_api_data(url)
        uri = URI(url)
        
        # 1. Set up the HTTP request manually to allow for headers
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        
        request = Net::HTTP::Get.new(uri)
        
        # 2. Spoof a standard User-Agent so WAFs don't block the Ruby default bot
        request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 RailsApp/8.0" 
        request["Accept"] = "application/json"
        
        request['Authorization'] = "Bearer #{Setting.get("uex_api_token")}"

        response = http.request(request)

        # 3. Handle the response based on the HTTP Status Code
        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        elsif response.is_a?(Net::HTTPRedirection)
          Rails.logger.error "Redirected (StationsImporter): #{url} -> #{response['location']}"
          nil
        else
          # Log the exact status code and the first 200 characters of the body to diagnose further blocks
          Rails.logger.error "HTTP Error (StationsImporter): #{response.code} #{response.message} at #{url} - Body: #{response.body[0..200]}"
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "JSON Parsing Error (StationsImporter): #{e.message} at #{url}"
        nil
      rescue => e
        Rails.logger.error "Network Error (StationsImporter): #{e.message} at #{url}"
        nil
      end

      def self.determine_parent_name(data)
        data['moon_name'] ||
        data['planet_name'] ||
        data['star_system_name'] # Defaults to Star System if all else is nil
      end
      
      def self.ensure_parent_exists(api_id, classification)
        return nil if api_id.to_i.zero?
        
        # Check if the parent location already exists
        parent = Location.find_by(api_id: api_id)
        return parent.id if parent
        
        # Create a placeholder parent if not found
        placeholder = Location.create!(
          api_id: api_id,
          name: "Placeholder #{classification.capitalize} (ID: #{api_id})",
          classification: classification,
          is_available: false,
          is_visible: false
        )
          
        Rails.logger.info "Created placeholder for missing parent: #{placeholder.name} with ID #{placeholder.id}"
        placeholder.id
      end
        
    end
  end
end