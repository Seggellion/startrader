module Admin
  module Data
    class ShipsImporter
      # 📥 Import ships strictly from the pasted JSON string
      def self.import_raw_json!(json_string)
        imported_count = 0
        data = JSON.parse(json_string)

        return 0 unless data&.any?

        # Safely extract the array whether it's wrapped in { "data": [...] } or just [...]
        records_array = data['data'] || data

        records_array.each do |ship_data|
          if import_ship(ship_data)
            imported_count += 1
          end
        end

        Rails.logger.info "Successfully imported #{imported_count} ships via raw JSON."
        imported_count
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (ShipsImporter): #{e.message}"
        0
      rescue => e
        Rails.logger.error "Failed to import raw JSON ships: #{e.message}"
        0
      end

      # 🧠 Handle the mapping for a single ship
      def self.import_ship(data)
        ship = Ship.find_or_initialize_by(api_id: data['id'])
        
        ship.assign_attributes(
          model: data['name'],
          name: data['name'],
          name_full: data['name_full'],
          slug: data['slug'],
          id_company: data['id_company'],
          id_parent: data['id_parent'],
          ids_vehicles_loaners: data['ids_vehicles_loaners'],
          scu: data['scu'],
          crew: data['crew'].to_i,
          mass: data['mass'],
          width: data['width'],
          height: data['height'],
          length: data['length'],
          fuel_quantum: data['fuel_quantum'],
          fuel_hydrogen: data['fuel_hydrogen'],
          container_sizes: data['container_sizes'],
          pad_type: data['pad_type'],
          game_version: data['game_version'],
          company_name: data['company_name'],
          url_photo: data['url_photo'],
          url_store: data['url_store'],
          url_brochure: data['url_brochure'],
          url_hotsite: data['url_hotsite'],
          url_video: data['url_video'],
          url_photos: data['url_photos'],
          date_added: data['date_added'],
          date_modified: data['date_modified'],

          # Boolean flags
          is_addon: data['is_addon'].to_i == 1,
          is_boarding: data['is_boarding'].to_i == 1,
          is_bomber: data['is_bomber'].to_i == 1,
          is_cargo: data['is_cargo'].to_i == 1,
          is_carrier: data['is_carrier'].to_i == 1,
          is_civilian: data['is_civilian'].to_i == 1,
          is_concept: data['is_concept'].to_i == 1,
          is_construction: data['is_construction'].to_i == 1,
          is_datarunner: data['is_datarunner'].to_i == 1,
          is_docking: data['is_docking'].to_i == 1,
          is_emp: data['is_emp'].to_i == 1,
          is_exploration: data['is_exploration'].to_i == 1,
          is_ground_vehicle: data['is_ground_vehicle'].to_i == 1,
          is_hangar: data['is_hangar'].to_i == 1,
          is_industrial: data['is_industrial'].to_i == 1,
          is_interdiction: data['is_interdiction'].to_i == 1,
          is_loading_dock: data['is_loading_dock'].to_i == 1,
          is_medical: data['is_medical'].to_i == 1,
          is_military: data['is_military'].to_i == 1,
          is_mining: data['is_mining'].to_i == 1,
          is_passenger: data['is_passenger'].to_i == 1,
          is_qed: data['is_qed'].to_i == 1,
          is_racing: data['is_racing'].to_i == 1,
          is_refinery: data['is_refinery'].to_i == 1,
          is_refuel: data['is_refuel'].to_i == 1,
          is_repair: data['is_repair'].to_i == 1,
          is_research: data['is_research'].to_i == 1,
          is_salvage: data['is_salvage'].to_i == 1,
          is_scanning: data['is_scanning'].to_i == 1,
          is_science: data['is_science'].to_i == 1,
          is_showdown_winner: data['is_showdown_winner'].to_i == 1,
          is_spaceship: data['is_spaceship'].to_i == 1,
          is_starter: data['is_starter'].to_i == 1,
          is_stealth: data['is_stealth'].to_i == 1,
          is_tractor_beam: data['is_tractor_beam'].to_i == 1,
          is_quantum_capable: data['is_quantum_capable'].to_i == 1
        )
        
        ship.save!
      rescue => e
        Rails.logger.error "Failed to import ship #{data['name']}: #{e.message}"
        false
      end
    end
  end
end