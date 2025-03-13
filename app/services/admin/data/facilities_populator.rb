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
    
      # 🛠️ Helper Method to Import a Single Price Record
      def self.import_single_price(price_data)

        terminal = Terminal.find_by(api_id: price_data['id_terminal'])
        return unless terminal
        
        # 🔍 1. Attempt to match a `Location` in priority order
        location = terminal.location
        
        unless location
          Rails.logger.error "No matching location found for Terminal ID #{terminal.api_id} (#{terminal.nickname})"
          return
        end

        Rails.logger.info "Assigning Location ID #{location.id} (#{location.name}) to ProductionFacility for Commodity #{price_data['commodity_name']}"

        max_inventory = max_inventory_for_location(location.classification)
#location name is not populating correctly, and some locations have both sets of prices.

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
          production_rate: price_data['price_buy'].to_f > 0 ? 5 : 0,
          consumption_rate: price_data['price_sell'].to_f > 0 ? 5 : 0,
          location_name: location.name,
          max_inventory: max_inventory
        )
    
        facility.save!
      end


      # 📍 Determine Max Inventory by Location Type
      def self.max_inventory_for_location(classification)
        case classification
        when 'space_station' then 25000
        when 'city' then 1000
        when 'outpost' then 5000
        when 'poi' then 1000
        when 'moon' then 200
        when 'planet' then 200
        else 50 # Default for unknown classifications
        end
      end

      # 📍 Prioritized Location Matching Method
      def self.find_best_matching_location(data)
        # 1. Check for Space Station
        
        location = Location.find_by(id_space_station: data['id_space_station'])
        return location if location

        # 2. Check for City
        location = Location.find_by(id_city: data['id_city'])
        return location if location

        # 3. Check for Outpost
        location = Location.find_by(id_outpost: data['id_outpost'])
        return location if location

        # 4. Check for Point of Interest (POI)
        location = Location.find_by(id_poi: data['id_poi'])
        return location if location

        # 5. Check for Moon
        location = Location.find_by(id_moon: data['id_moon'])
        return location if location

        # 6. Fallback to Planet
        location = Location.find_by(id_planet: data['id_planet'])
        return location if location

        # 7. Final Fallback: Log Missing Location
        Rails.logger.warn "No specific location found for data: #{data.inspect}"
        nil
      end

      # 📡 Fetch API Data Helper Method
      def self.fetch_api_data(url)
        response = Net::HTTP.get(URI(url))
        JSON.parse(response)
      rescue => e
        Rails.logger.error "Failed to fetch data (FacilitiesPopulator): #{e.message}"
        nil
      end
    end
  end
end
