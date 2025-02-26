module Admin
    module Data
      class CommoditiesImporter
        # Import a single commodity, return true/false indicating success

        API_URL = "https://api.uexcorp.space/2.0/commodities"


        def self.import_all!
          data = fetch_api_data(API_URL)
          return 0 unless data&.any?
      
          imported_count = 0
      
          commodity_data = data['data'] || data
          commodity_data.each do |commodity_data|
            commodity = Commodity.find_or_initialize_by(api_id: commodity_data['id'])
      
            commodity.assign_attributes(
              id_parent: commodity_data['id_parent'],
              name: commodity_data['name'],
              code: commodity_data['code'],
              kind: commodity_data['kind'],
              weight_scu: commodity_data['weight_scu'],
              price_buy: commodity_data['price_buy'],
              price_sell: commodity_data['price_sell'],
              is_available: commodity_data['is_available'],
              is_visible: commodity_data['is_visible'],
              is_buyable: commodity_data['is_buyable'],
              is_sellable: commodity_data['is_sellable'],
              is_illegal: commodity_data['is_illegal'],
              wiki: commodity_data['wiki'],
              date_added: commodity_data['date_added'],
              date_modified: commodity_data['date_modified']
            )
      
            commodity.save!
            imported_count += 1
          end
      
          imported_count
        rescue => e
          Rails.logger.error "Failed to import commodities: #{e.message}"
          0
        end

        def self.import_single!
          data = fetch_api_data(API_URL)

          return false unless data&.any?
  
          # Some endpoints have a nested "data" key, others don't
          commodity_data = data['data'] ? data['data'].first : data.first
          return false unless commodity_data
  
          commodity = Commodity.find_or_initialize_by(api_id: commodity_data['id'])
          commodity.assign_attributes(
            id_parent: commodity_data['id_parent'],
            name: commodity_data['name'],
            code: commodity_data['code'],
            kind: commodity_data['kind'],
            weight_scu: commodity_data['weight_scu'],
            price_buy: commodity_data['price_buy'],
            price_sell: commodity_data['price_sell'],
            is_available: commodity_data['is_available'],
            is_visible: commodity_data['is_visible'],
            is_buyable: commodity_data['is_buyable'],
            is_sellable: commodity_data['is_sellable'],
            is_illegal: commodity_data['is_illegal'],
            wiki: commodity_data['wiki'],
            date_added: commodity_data['date_added'],
            date_modified: commodity_data['date_modified']
          )
          
          commodity.save!
          true
        rescue => e
          Rails.logger.error "Failed to import commodity: #{e.message}"
          false
        end
  
        # Make this a **class method** so it can be called from `import_single!`
        def self.fetch_api_data(url)
          response = Net::HTTP.get(URI(url))
          JSON.parse(response)
        rescue => e
          Rails.logger.error "Failed to fetch data (CommoditiesImporter): #{e.message}"
          nil
        end
      end
    end
  end
  