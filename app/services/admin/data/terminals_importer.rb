module Admin
  module Data
    class TerminalsImporter


  # 🆕 Import a **single terminal** for testing purposes
  def self.import_single!
    url = "https://api.uexcorp.space/2.0/terminals"
    data = fetch_api_data(url)
    return false unless data&.any?

    terminal_data = data['data'].first
    return false unless terminal_data

    # Find or initialize the terminal by API ID
    terminal = Terminal.find_or_initialize_by(api_id: terminal_data['id'])
    
    # Map attributes from the API to the Terminal model
    terminal.assign_attributes(
      api_id: terminal_data['id'],
      code: terminal_data['code'],
      name: terminal_data['name'],
      nickname: terminal_data['nickname'],
      id_star_system: terminal_data['id_star_system'],
      id_planet: terminal_data['id_planet'],
      id_orbit: terminal_data['id_orbit'],
      id_moon: terminal_data['id_moon'],
      id_space_station: terminal_data['id_space_station'],
      id_city: terminal_data['id_city'],
      id_faction: terminal_data['id_faction'],
      id_company: terminal_data['id_company'],
      max_container_size: terminal_data['max_container_size']
    )
    
    terminal.save!
    Rails.logger.info "Successfully imported terminal: #{terminal.name}"
    true
  rescue => e
    Rails.logger.error "Failed to import single terminal: #{e.message}"
    false
  end

      def self.import_all!
        url = "https://api.uexcorp.space/2.0/terminals"
        data = fetch_api_data(url)
        return 0 unless data&.any?

        # The API might return an array. Let's store how many we import
        imported_count = 0

        data['data'].each do |terminal_data|
          terminal = Terminal.find_or_initialize_by(api_id: terminal_data['id'])

          terminal.code = terminal_data['code']
          terminal.name = terminal_data['name']
          terminal.nickname = terminal_data['nickname']
          terminal.id_star_system = terminal_data['id_star_system']
          terminal.id_planet = terminal_data['id_planet']
          terminal.id_orbit = terminal_data['id_orbit']
          terminal.id_moon = terminal_data['id_moon']
          terminal.id_space_station = terminal_data['id_space_station']
          terminal.id_city = terminal_data['id_city']
          terminal.id_faction = terminal_data['id_faction']
          terminal.id_company = terminal_data['id_company']
          terminal.max_container_size = terminal_data['max_container_size']
          
          terminal.save!
          imported_count += 1
        end
        imported_count
      rescue => e
        Rails.logger.error "Failed to import terminals: #{e.message}"
        0
      end

      def self.fetch_api_data(url)
        response = Net::HTTP.get(URI(url))
        JSON.parse(response)
      rescue => e
        Rails.logger.error "Failed to fetch data (TerminalsImporter): #{e.message}"
        nil
      end



    end
  end
end
