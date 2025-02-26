module Admin
    module Data
      class FacilitiesPopulator
       

        
        API_URL = "https://api.uexcorp.space/2.0/commodities_prices_all"

        # 🚚 Import All Commodity Prices
        def self.import_all!
          data = fetch_api_data(API_URL)
          return 0 unless data&.any?
      
          imported_count = 0
          price_data_array = data['data'] || data
      
          price_data_array.each do |price_data|
            import_single_price(price_data)
            imported_count += 1
          end
      
          imported_count
        rescue => e
          Rails.logger.error "Failed to import all commodity prices: #{e.message}"
          0
        end
      
        # 💰 Import a Single Commodity Price
        def self.import_single!
          data = fetch_api_data(API_URL)
          return false unless data&.any?
      
          price_data = data['data'].first
          return false unless price_data
      
          import_single_price(price_data)
          true
        rescue => e
          Rails.logger.error "Failed to import single commodity price: #{e.message}"
          false
        end
      
        # 🛠️ Helper Method to Import a Single Price Record
        def self.import_single_price(price_data)
          terminal = Terminal.find_by(api_id: price_data['id_terminal'])

          
          return unless terminal
      

            location = Location.where(
            id_star_system: terminal.id_star_system,
            id_faction: terminal.id_faction
          ).where(
            "(id_planet = :id_planet AND id_orbit = :id_orbit) OR (id_moon = :id_moon)",
            id_planet: terminal.id_planet,
            id_orbit: terminal.id_orbit,
            id_moon: terminal.id_moon
          ).first
      unless location    
byebug
      end
      #    location = Location.find_by(nickname: terminal.nickname)
      
          facility = ProductionFacility.find_or_initialize_by(api_id: price_data['id'])
          facility.assign_attributes(
            id_commodity: price_data['id_commodity'],
            commodity_id: price_data['id_commodity'],
            id_terminal: price_data['id_terminal'],
            price_buy: price_data['price_buy'],
            price_sell: price_data['price_sell'],
            scu_sell_stock: price_data['scu_sell_stock'],
            status_buy: price_data['status_buy'],
            status_sell: price_data['status_sell'],
            commodity_name: price_data['commodity_name'],
            facility_name: price_data['terminal_name'],
            terminal_name: price_data['terminal_name'],
            production_rate: 5,
            consumption_rate: 1,
            location_id: location&.id
          )
      
          facility.save!
        end
      
      def self.fetch_api_data(url)
        response = Net::HTTP.get(URI(url))
        JSON.parse(response)
      rescue => e
        Rails.logger.error "Failed to fetch data (LocationsImporter): #{e.message}"
        nil
      end





      end
    end
  end
  