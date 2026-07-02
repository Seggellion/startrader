require "net/http"
require "json"

module Admin
  module Data
    class CommoditiesImporter
      API_URL = "https://api.uexcorp.space/2.0/commodities".freeze

      COMMODITY_MAPPINGS = {
        "id" => "api_id",
        "id_parent" => "id_parent",
        "name" => "name",
        "code" => "code",
        "kind" => "kind",
        "weight_scu" => "weight_scu",
        "price_buy" => "price_buy",
        "price_sell" => "price_sell",
        "is_available" => "is_available",
        "is_available_live" => "is_available_live",
        "is_visible" => "is_visible",
        "is_mineral" => "is_mineral",
        "is_raw" => "is_raw",
        "is_refined" => "is_refined",
        "is_harvestable" => "is_harvestable",
        "is_buyable" => "is_buyable",
        "is_sellable" => "is_sellable",
        "is_temporary" => "is_temporary",
        "is_illegal" => "is_illegal",
        "is_fuel" => "is_fuel",
        "wiki" => "wiki",
        "date_added" => "date_added",
        "date_modified" => "date_modified"
      }.freeze

      def self.import_all!
        payload = fetch_api_data(API_URL)
        import_records(extract_records(payload))
      rescue => e
        Rails.logger.error "Failed to import commodities (CommoditiesImporter): #{e.message}"
        0
      end

      def self.import_raw_json!(json_string)
        payload = JSON.parse(json_string)
        import_records(extract_records(payload))
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (CommoditiesImporter): #{e.message}"
        0
      rescue => e
        Rails.logger.error "Failed to import raw JSON commodities (CommoditiesImporter): #{e.message}"
        0
      end

      def self.import_single!
        payload = fetch_api_data(API_URL)
        commodity_data = extract_records(payload)&.first
        return false unless commodity_data

        import_commodity(commodity_data)
      rescue => e
        Rails.logger.error "Failed to import commodity (CommoditiesImporter): #{e.message}"
        false
      end

      def self.import_records(records)
        return 0 unless records&.any?

        imported_count = records.sum { |commodity_data| import_commodity(commodity_data) ? 1 : 0 }
        Rails.logger.info "Successfully imported #{imported_count} commodities (CommoditiesImporter)."
        imported_count
      end

      def self.extract_records(payload)
        if payload.is_a?(Hash)
          return payload["data"] if payload["data"].is_a?(Array)

          Rails.logger.error "Unsupported commodities payload data shape (CommoditiesImporter): #{payload['data'].class}"
          nil
        elsif payload.is_a?(Array)
          payload
        else
          Rails.logger.error "Unsupported commodities payload shape (CommoditiesImporter): #{payload.class}"
          nil
        end
      end

      def self.import_commodity(commodity_data)
        return log_skipped_commodity(commodity_data, "row is not an object") unless commodity_data.is_a?(Hash)

        commodity = find_or_initialize_commodity(commodity_data)
        commodity.assign_attributes(commodity_attributes(commodity_data))

        if commodity.save
          Rails.logger.info "Successfully imported commodity: #{commodity.name} (api_id=#{commodity.api_id})"
          true
        else
          Rails.logger.error "Failed to save commodity (#{commodity.name}): #{commodity.errors.full_messages.join(', ')}"
          false
        end
      rescue => e
        Rails.logger.error "Failed to import commodity (#{commodity_data&.[]('name') || 'unknown'}): #{e.message}"
        false
      end

      def self.find_or_initialize_commodity(commodity_data)
        api_id = integer_or_nil(commodity_data["id"])
        return Commodity.find_or_initialize_by(api_id: api_id) if api_id && Commodity.exists?(api_id: api_id)

        legacy_commodity = find_legacy_commodity(commodity_data)
        return legacy_commodity if legacy_commodity

        Commodity.new(api_id: api_id)
      end

      def self.find_legacy_commodity(commodity_data)
        code = commodity_data["code"].presence
        if code
          by_code = Commodity.where(code: code).to_a
          return by_code.first if by_code.one?
          raise "ambiguous commodity code #{code.inspect}" if by_code.many?
        end

        name = commodity_data["name"].presence
        return unless name

        by_name = Commodity.where(name: name).to_a
        raise "ambiguous commodity name #{name.inspect}" if by_name.many?

        by_name.first if by_name.one?
      end

      def self.commodity_attributes(commodity_data)
        COMMODITY_MAPPINGS.each_with_object({}) do |(payload_key, attribute), attributes|
          next unless Commodity.column_names.include?(attribute)

          value = commodity_data[payload_key]
          value = cast_attribute_value(attribute, value)
          attributes[attribute] = value
        end
      end

      def self.cast_attribute_value(attribute, value)
        column = Commodity.columns_hash[attribute]

        case column&.type
        when :boolean
          boolean_type.cast(value)
        when :integer
          integer_or_nil(value)
        else
          value
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
          Rails.logger.error "Redirected (CommoditiesImporter): #{url} -> #{response['location']}"
          nil
        else
          Rails.logger.error "HTTP Error (CommoditiesImporter): #{response.code} #{response.message} at #{url} - Body: #{response.body.to_s[0..200]}"
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "JSON Parsing Error (CommoditiesImporter): #{e.message} at #{url}"
        nil
      rescue => e
        Rails.logger.error "Network Error (CommoditiesImporter): #{e.message} at #{url}"
        nil
      end

      def self.boolean_type
        @boolean_type ||= ActiveModel::Type::Boolean.new
      end

      def self.integer_or_nil(value)
        return if value.blank?

        value.to_i
      end

      def self.log_skipped_commodity(commodity_data, reason)
        Rails.logger.warn "Skipped commodity row (CommoditiesImporter): #{reason}; row=#{commodity_data.inspect}"
        false
      end
    end
  end
end
