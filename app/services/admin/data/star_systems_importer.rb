module Admin
  module Data
    class StarSystemsImporter
      LOCATION_URLS = [
        "https://api.uexcorp.space/2.0/star_systems"
      ].freeze

      def self.import_all!
        imported_count = 0

        LOCATION_URLS.each do |url|
          data = fetch_api_data(url)
          next unless data&.any?

          locations_array = locations_from_response(data)
          next unless locations_array&.any?

          locations_array.each do |location_data|
            imported_count += 1 if import_location(location_data)
          end
        end

        Rails.logger.info "Successfully imported #{imported_count} star systems."
        imported_count
      rescue => e
        Rails.logger.error "Failed to import all star systems: #{e.message}"
        0
      end

      def self.import_raw_json!(json_string)
        imported_count = 0
        data = JSON.parse(json_string)

        locations_array = locations_from_response(data)
        return 0 unless locations_array&.any?

        locations_array.each do |location_data|
          imported_count += 1 if import_location(location_data)
        end

        Rails.logger.info "Successfully imported #{imported_count} star systems via raw JSON."
        imported_count
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (StarSystemsImporter): #{e.message}"
        0
      rescue => e
        Rails.logger.error "Failed to import raw JSON star systems: #{e.message}"
        0
      end

      def self.import_single!
        LOCATION_URLS.each do |url|
          data = fetch_api_data(url)
          next unless data&.any?

          locations_array = locations_from_response(data)
          next unless locations_array&.any?

          return true if import_location(locations_array.first)
        end

        false
      end

      def self.import_location(location_data)
        classification = "star_system"

        location = Location.find_or_initialize_by(
          api_id: location_data["id"],
          classification: classification
        )

        location.assign_attributes(
          name: location_data["name"],
          nickname: location_data["nickname"],
          classification: classification,
          code: location_data["code"],
          api_id: location_data["id"],
          parent_name: nil,
          id_star_system: location_data["id_star_system"],
          id_planet: location_data["id_planet"],
          id_orbit: location_data["id_orbit"],
          id_moon: location_data["id_moon"],
          id_space_station: location_data["id_space_station"],
          id_outpost: location_data["id_outpost"],
          id_poi: location_data["id_poi"],
          id_city: location_data["id_city"],
          id_faction: location_data["id_faction"],
          id_company: location_data["id_company"],
          api_type: location_data["type"],
          mass: 166_500_000,
          periapsis: 0,
          apoapsis: 0,

          is_available: bool(location_data, "is_available"),
          is_available_live: bool(location_data, "is_available_live"),
          is_visible: bool(location_data, "is_visible"),
          is_default_system: bool(location_data, "is_default", "is_default_system"),
          is_affinity_influenceable: bool(location_data, "is_affinity_influenceable"),
          is_habitation: bool(location_data, "is_habitation"),
          is_refinery: bool(location_data, "is_refinery"),
          is_cargo_center: bool(location_data, "is_cargo_center"),
          is_medical: bool(location_data, "is_medical"),
          is_food: bool(location_data, "is_food"),
          is_shop_fps: bool(location_data, "is_shop_fps"),
          is_shop_vehicle: bool(location_data, "is_shop_vehicle"),
          is_refuel: bool(location_data, "is_refuel"),
          is_repair: bool(location_data, "is_repair"),
          is_nqa: bool(location_data, "is_nqa"),
          is_player_owned: bool(location_data, "is_player_owned"),
          is_auto_load: bool(location_data, "is_auto_load"),
          has_loading_dock: bool(location_data, "has_loading_dock"),
          has_docking_port: bool(location_data, "has_docking_port"),
          has_freight_elevator: bool(location_data, "has_freight_elevator"),

          star_system_name: location_data["star_system_name"] || location_data["name"],
          planet_name: location_data["planet_name"],
          orbit_name: location_data["orbit_name"],
          moon_name: location_data["moon_name"],
          space_station_name: location_data["space_station_name"],
          outpost_name: location_data["outpost_name"],
          city_name: location_data["city_name"],
          faction_name: location_data["faction_name"],
          company_name: location_data["company_name"],

          max_container_size: location_data["max_container_size"].to_i,
          date_added: location_data["date_added"].to_i,
          date_modified: location_data["date_modified"].to_i
        )

        location.save!
      rescue => e
        Rails.logger.error "Failed to import star system #{location_data&.[]("name") || "unknown"}: #{e.message}"
        false
      end

      def self.fetch_api_data(url)
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 RailsApp/8.0"
        request["Accept"] = "application/json"
        request["Authorization"] = "Bearer #{Setting.get("uex_api_token")}"

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        elsif response.is_a?(Net::HTTPRedirection)
          Rails.logger.error "Redirected (StarSystemsImporter): #{url} -> #{response["location"]}"
          nil
        else
          Rails.logger.error "HTTP Error (StarSystemsImporter): #{response.code} #{response.message} at #{url} - Body: #{response.body[0..200]}"
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "JSON Parsing Error (StarSystemsImporter): #{e.message} at #{url}"
        nil
      rescue => e
        Rails.logger.error "Network Error (StarSystemsImporter): #{e.message} at #{url}"
        nil
      end

      def self.locations_from_response(data)
        if data.is_a?(Hash)
          data["data"] if data["data"].is_a?(Array)
        elsif data.is_a?(Array)
          data
        end
      end

      def self.bool(data, *keys)
        return false unless data.respond_to?(:key?)

        key = keys.find { |candidate| data.key?(candidate) }
        return false unless key

        value = data[key]
        return false if value.nil?
        return value if value == true || value == false
        return true if value.to_s == "true"

        value.respond_to?(:to_i) && value.to_i == 1
      end
    end
  end
end
