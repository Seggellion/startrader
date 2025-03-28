# app/services/admin/data/facilities_populator.rb
module Admin
  module Data
    class FacilitiesPopulator
      API_URL = "https://api.uexcorp.space/2.0/commodities_prices_all".freeze
      BATCH_SIZE = 500

      # 🚚 Import All Commodity Prices
      def self.import_all!
        # Fetch and parse the API data
        data = fetch_api_data(API_URL)
        return 0 unless data&.any?

        price_data_array = data['data'] || data

        total_imported = 0

        # Slice the data into chunks to avoid large single-batch overhead
        price_data_array.each_slice(BATCH_SIZE) do |batch|
          upsert_data = []

          batch.each do |price_data|
            # We only build attributes if we can actually match the terminal+location
            next unless (terminal = Terminal.find_by(api_id: price_data['id_terminal']))
            next unless (location = terminal.location)

            upsert_data << build_attributes(price_data, location)
          rescue => e
            # Log and skip any record that triggers an exception building attributes
            Rails.logger.error "Error building attributes for price_data=#{price_data.inspect}: #{e.message}"
          end

          # Perform bulk upsert
          if upsert_data.any?
            result = ProductionFacility.upsert_all(
              upsert_data,
              unique_by: :api_id
            )
            Rails.logger.info("Upsert result: #{result.inspect}")
            total_imported += upsert_data.size
          end
        end

        total_imported
      rescue => e
        Rails.logger.error "Failed to import all commodity prices: #{e.message}"
        0
      end

      # Build the facility attribute hash for upsert
      def self.build_attributes(price_data, location)
        {
          api_id:           price_data['id'],
          id_commodity:     price_data['id_commodity'],
          id_terminal:      price_data['id_terminal'],
          price_buy:        price_data['price_buy'],
          price_sell:       price_data['price_sell'],
          scu_sell_stock:   price_data['scu_sell_stock'],
          status_buy:       price_data['status_buy'],
          status_sell:      price_data['status_sell'],
          commodity_name:   price_data['commodity_name'],
          facility_name:    price_data['terminal_name'],
          terminal_name:    price_data['terminal_name'],
          production_rate:  price_data['price_buy'].to_f > 0 ? 5 : 0,
          consumption_rate: price_data['price_sell'].to_f > 0 ? 5 : 0,
          location_name:    location.name,
          max_inventory:    max_inventory_for_location(location.classification),
          # Timestamps – upsert_all does not handle automatically, so we must provide
          updated_at:       Time.current,
          created_at:       Time.current
        }
      end

      # 📍 Determine Max Inventory by Location Type
      def self.max_inventory_for_location(classification)
        case classification
        when 'space_station' then 25_000
        when 'city'          then 1_000
        when 'outpost'       then 5_000
        when 'poi'           then 1_000
        when 'moon'          then 200
        when 'planet'        then 200
        else 50 # Default for unknown classifications
        end
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
