module Admin
  module Data
    class TerminalsImporter

      API_URL = "https://api.uexcorp.space/2.0/terminals".freeze
      TERMINAL_ATTRIBUTES = %w[
        api_id code name nickname id_star_system id_planet 
        id_orbit id_moon id_space_station id_city 
        id_faction id_company max_container_size
      ].freeze

      # 🆕 Import a **single terminal** for testing purposes
      def self.import_single!
        data = fetch_api_data
        return false unless data&.any?

        terminal_data = data['data'].first
        return false unless terminal_data

        import_terminal(terminal_data)
      rescue => e
        Rails.logger.error "Failed to import single terminal: #{e.message}"
        false
      end

      # 🚚 Import All Terminals from the API
      def self.import_all!
        data = fetch_api_data
        return 0 unless data&.any?

        data['data'].sum { |terminal_data| import_terminal(terminal_data) ? 1 : 0 }
      rescue => e
        Rails.logger.error "Failed to import terminals: #{e.message}"
        0
      end

      # 📡 Fetch Data from the API
      def self.fetch_api_data
        response = Net::HTTP.get(URI(API_URL))
        JSON.parse(response)
      rescue => e
        Rails.logger.error "Failed to fetch data (TerminalsImporter): #{e.message}"
        nil
      end

      # 🛠️ Import or Update a Single Terminal
      def self.import_terminal(terminal_data)
        terminal = Terminal.find_or_initialize_by(api_id: terminal_data['id'])

        # Assign standard terminal attributes
        terminal.assign_attributes(terminal_data.slice(*TERMINAL_ATTRIBUTES))

        # Dynamically assign location_name based on priority
        terminal.location_name = determine_location_name(terminal_data)

        if terminal.save
          Rails.logger.info "Successfully imported terminal: #{terminal.name} (Location: #{terminal.location_name})"
          true
        else
          Rails.logger.error "Failed to save terminal (#{terminal.name}): #{terminal.errors.full_messages.join(', ')}"
          false
        end
      rescue => e
        Rails.logger.error "Failed to import terminal (#{terminal_data['name']}): #{e.message}"
        false
      end

      # 🔍 Determine the Best Matching `location_name`
      def self.determine_location_name(data)
        data['city_name'] ||
        data['space_station_name'] ||
        data['outpost_name'] ||
        data['poi_name'] ||
        data['moon_name'] ||
        data['planet_name']
      end

    end
  end
end
