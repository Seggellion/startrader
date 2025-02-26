# app/services/admin/data/ships_importer.rb
module Admin
    module Data
      class ShipsImporter
        def self.import_single!
          url = "https://api.uexcorp.space/2.0/vehicles"
          data = fetch_api_data(url)
          return false unless data&.any?
  
          ship_data = data.first
          ship = Ship.find_or_initialize_by(api_id: ship_data['id'])
          ship.assign_attributes(
            id_company: ship_data['id_company'],
            id_parent: ship_data['id_parent'],
            name: ship_data['name'],
            name_full: ship_data['name_full'],
            slug: ship_data['slug'],
            scu: ship_data['scu'],
            crew: ship_data['crew'],
            mass: ship_data['mass'],
            length: ship_data['length'],
            width: ship_data['width'],
            height: ship_data['height'],
            fuel_quantum: ship_data['fuel_quantum'],
            fuel_hydrogen: ship_data['fuel_hydrogen'],
            container_sizes: ship_data['container_sizes'],
            pad_type: ship_data['pad_type'],
            game_version: ship_data['game_version'],
            date_added: ship_data['date_added'],
            date_modified: ship_data['date_modified'],
            company_name: ship_data['company_name'],
            url_store: ship_data['url_store'],
            url_brochure: ship_data['url_brochure'],
            url_hotsite: ship_data['url_hotsite'],
            url_video: ship_data['url_video'],
            url_photos: ship_data['url_photos'],
            is_ground_vehicle: ship_data['is_ground_vehicle'],
            is_military: ship_data['is_military'],
            is_spaceship: ship_data['is_spaceship']
          )
          ship.save!
        end
  
        def self.fetch_api_data(url)
          response = Net::HTTP.get(URI(url))
          JSON.parse(response)
        rescue => e
          Rails.logger.error "Failed to fetch data (ShipsImporter): #{e.message}"
          nil
        end
      end
    end
  end
  