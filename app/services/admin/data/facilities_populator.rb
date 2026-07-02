require "net/http"
require "json"
require "set"

module Admin
  module Data
    class FacilitiesPopulator
      API_URL = "https://api.uexcorp.space/2.0/commodities_prices_all".freeze
      BATCH_SIZE = 500

      def self.import_all!
        payload = fetch_api_data(API_URL)
        replace_all_from_payload!(payload)
      rescue => e
        Rails.logger.error "Failed to import all commodity prices (FacilitiesPopulator): #{e.message}"
        0
      end

      def self.import_raw_json!(json_string)
        payload = JSON.parse(json_string)
        replace_all_from_payload!(payload)
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (FacilitiesPopulator): #{e.message}"
        0
      rescue => e
        Rails.logger.error "Failed to import raw JSON facilities (FacilitiesPopulator): #{e.message}"
        0
      end

      def self.replace_all_from_payload!(payload)
        price_data_array = records_from_response(payload)
        return 0 unless price_data_array&.any?

        imported_count = 0

        ProductionFacility.without_market_broadcasts do
          ProductionFacility.transaction do
            ProductionFacility.delete_all
            seen_api_ids = Set.new

            price_data_array.each_slice(BATCH_SIZE) do |batch|
              records = build_batch_attributes(batch, seen_api_ids)
              next if records.empty?

              ProductionFacility.insert_all(records, unique_by: :index_production_facilities_on_api_id)
              imported_count += records.size
            end
          end
        end

        Rails.logger.info "Successfully replaced ProductionFacility data with #{imported_count} facilities (FacilitiesPopulator)."
        imported_count
      rescue => e
        Rails.logger.error "Failed to replace ProductionFacility data (FacilitiesPopulator): #{e.message}"
        0
      end

      def self.records_from_response(payload)
        if payload.is_a?(Hash)
          return payload["data"] if payload["data"].is_a?(Array)

          Rails.logger.error "Unsupported facilities payload data shape (FacilitiesPopulator): #{payload['data'].class}"
          nil
        elsif payload.is_a?(Array)
          payload
        else
          Rails.logger.error "Unsupported facilities payload shape (FacilitiesPopulator): #{payload.class}"
          nil
        end
      end

      def self.build_batch_attributes(batch, seen_api_ids = Set.new)
        batch.filter_map do |price_data|
          next log_skipped_row(price_data, "row is not an object") unless price_data.is_a?(Hash)

          api_id = integer_value(price_data["id"], nil)
          next log_skipped_row(price_data, "missing id") if api_id.blank?
          next log_skipped_row(price_data, "duplicate id #{api_id}") if seen_api_ids.include?(api_id)

          seen_api_ids << api_id

          terminal = Terminal.find_by(api_id: integer_value(price_data["id_terminal"], nil))
          next log_skipped_row(price_data, "missing terminal id_terminal=#{price_data['id_terminal'].inspect}") unless terminal

          location = terminal.location
          next log_skipped_row(price_data, "terminal id_terminal=#{price_data['id_terminal'].inspect} has no location") unless location

          terminal_name = price_data["terminal_name"].presence || terminal.name.presence || terminal.nickname
          next log_skipped_row(price_data, "missing terminal_name") if terminal_name.blank?

          build_attributes(price_data, location, api_id, terminal_name)
        rescue => e
          Rails.logger.error "Error building facilities row (FacilitiesPopulator) price_data=#{price_data.inspect}: #{e.message}"
          nil
        end
      end

      def self.build_attributes(price_data, location, api_id, terminal_name)
        now = Time.current
        max_inventory = max_inventory_for_location(location.classification)
        inventory = inventory_for(price_data, max_inventory)

        {
          api_id: api_id,
          id_commodity: integer_value(price_data["id_commodity"], nil),
          id_terminal: integer_value(price_data["id_terminal"], nil),
          price_buy: decimal_value(price_data["price_buy"]),
          price_buy_avg: decimal_value(price_data["price_buy_avg"]),
          price_sell: decimal_value(price_data["price_sell"]),
          price_sell_avg: decimal_value(price_data["price_sell_avg"]),
          scu_buy: integer_value(price_data["scu_buy"]),
          scu_buy_avg: integer_value(price_data["scu_buy_avg"]),
          scu_sell_stock: integer_value(price_data["scu_sell_stock"]),
          scu_sell_stock_avg: integer_value(price_data["scu_sell_stock_avg"]),
          scu_sell: integer_value(price_data["scu_sell"]),
          scu_sell_avg: integer_value(price_data["scu_sell_avg"]),
          status_buy: integer_value(price_data["status_buy"]),
          status_sell: integer_value(price_data["status_sell"]),
          container_sizes: container_sizes_value(price_data["container_sizes"]),
          date_added: integer_value(price_data["date_added"], nil),
          date_modified: integer_value(price_data["date_modified"], nil),
          commodity_name: price_data["commodity_name"],
          facility_name: terminal_name,
          terminal_name: terminal_name,
          production_rate: decimal_value(price_data["price_buy"]).positive? ? 5 : 0,
          consumption_rate: decimal_value(price_data["price_sell"]).positive? ? 5 : 0,
          location_name: location.name,
          inventory: inventory,
          max_inventory: max_inventory,
          updated_at: now,
          created_at: now
        }
      end

      def self.max_inventory_for_location(classification)
        case classification
        when "space_station" then 25_000
        when "city"          then 1_000
        when "outpost"       then 5_000
        when "poi"           then 1_000
        when "moon"          then 200
        when "planet"        then 200
        else 50
        end
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
          Rails.logger.error "Redirected (FacilitiesPopulator): #{url} -> #{response['location']}"
          nil
        else
          Rails.logger.error "HTTP Error (FacilitiesPopulator): #{response.code} #{response.message} at #{url} - Body: #{response.body.to_s[0..200]}"
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "JSON Parsing Error (FacilitiesPopulator): #{e.message} at #{url}"
        nil
      rescue => e
        Rails.logger.error "Network Error (FacilitiesPopulator): #{e.message} at #{url}"
        nil
      end

      def self.inventory_for(price_data, max_inventory)
        raw_inventory = price_data.key?("inventory") ? price_data["inventory"] : price_data["scu_sell_stock"]
        inventory = integer_value(raw_inventory)

        return inventory if max_inventory.to_i <= 0

        [inventory, max_inventory].min
      end

      def self.integer_value(value, default = 0)
        return default if value.blank?

        value.to_i
      end

      def self.decimal_value(value)
        return 0.to_d if value.blank?

        value.to_d
      end

      def self.container_sizes_value(value)
        value.is_a?(Array) ? value.join(",") : value
      end

      def self.log_skipped_row(price_data, reason)
        Rails.logger.warn "Skipped facilities row (FacilitiesPopulator): #{reason}; row=#{price_data.inspect}"
        nil
      end
    end
  end
end
