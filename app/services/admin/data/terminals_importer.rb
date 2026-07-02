require "net/http"
require "json"

module Admin
  module Data
    class TerminalsImporter
      API_URL = "https://api.uexcorp.space/2.0/terminals".freeze
      SAMPLE_LIMIT = 10

      TERMINAL_MAPPINGS = {
        "id" => "api_id",
        "code" => "code",
        "name" => "name",
        "nickname" => "nickname",
        "id_star_system" => "id_star_system",
        "id_planet" => "id_planet",
        "id_orbit" => "id_orbit",
        "id_moon" => "id_moon",
        "id_space_station" => "id_space_station",
        "id_outpost" => "id_outpost",
        "id_poi" => "id_poi",
        "id_city" => "id_city",
        "id_faction" => "id_faction",
        "id_company" => "id_company",
        "max_container_size" => "max_container_size"
      }.freeze

      LOCATION_NAME_KEYS = %w[
        space_station_name
        city_name
        outpost_name
        poi_name
        moon_name
        planet_name
        star_system_name
      ].freeze

      LOCATION_API_ID_CANDIDATES = [
        ["id_space_station", "space_station"],
        ["id_city", "city"],
        ["id_outpost", "outpost"],
        ["id_poi", "poi"],
        ["id_moon", "moon"],
        ["id_planet", "planet"],
        ["id_star_system", "star_system"]
      ].freeze

      ImportResult = Struct.new(
        :total,
        :imported,
        :skipped,
        :failed,
        :missing_api_id,
        :missing_name,
        :missing_location,
        :validation_failed,
        :duplicate_identity_conflicts,
        :ambiguous_identity,
        :ambiguous_location,
        :fallback_location,
        :samples,
        keyword_init: true
      ) do
        def initialize(**kwargs)
          super(**{
            total: 0,
            imported: 0,
            skipped: 0,
            failed: 0,
            missing_api_id: 0,
            missing_name: 0,
            missing_location: 0,
            validation_failed: 0,
            duplicate_identity_conflicts: 0,
            ambiguous_identity: 0,
            ambiguous_location: 0,
            fallback_location: 0,
            samples: Hash.new { |hash, key| hash[key] = [] }
          }.merge(kwargs))
        end

        def to_i
          imported
        end

        def >(other)
          imported > other.to_i
        end

        def summary
          "Imported #{imported} terminals. Skipped #{skipped}. Failed #{failed}."
        end

        def log_line
          "TerminalsImporter summary: total=#{total} imported=#{imported} skipped=#{skipped} failed=#{failed} " \
            "missing_api_id=#{missing_api_id} missing_name=#{missing_name} missing_location=#{missing_location} " \
            "validation_failed=#{validation_failed} duplicate_identity_conflicts=#{duplicate_identity_conflicts} " \
            "ambiguous_identity=#{ambiguous_identity} ambiguous_location=#{ambiguous_location} fallback_location=#{fallback_location}"
        end
      end

      class AmbiguousIdentityError < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      class AmbiguousLocationError < StandardError
        attr_reader :reason

        def initialize(reason)
          @reason = reason
          super(reason)
        end
      end

      class << self
        attr_reader :last_import_result
      end

      def self.import_single!
        payload = fetch_api_data
        terminals = records_from_response(payload)
        return false unless terminals&.any?

        result = ImportResult.new(total: 1)
        import_terminal(terminals.first, result)
      rescue => e
        Rails.logger.error "Failed to import single terminal (TerminalsImporter): #{e.message}"
        false
      end

      def self.import_all!
        payload = fetch_api_data
        import_records(records_from_response(payload))
      rescue => e
        Rails.logger.error "Failed to import terminals (TerminalsImporter): #{e.message}"
        result = ImportResult.new(failed: 1)
        @last_import_result = result
        result
      end

      def self.import_raw_json!(json_string)
        payload = JSON.parse(json_string)
        import_records(records_from_response(payload))
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse pasted JSON (TerminalsImporter): #{e.message}"
        result = ImportResult.new(failed: 1)
        @last_import_result = result
        result
      rescue => e
        Rails.logger.error "Failed to import raw JSON terminals (TerminalsImporter): #{e.message}"
        result = ImportResult.new(failed: 1)
        @last_import_result = result
        result
      end

      def self.import_records(terminals)
        result = ImportResult.new(total: terminals&.size.to_i)

        if terminals&.any?
          terminals.each { |terminal_data| import_terminal(terminal_data, result) }
        end

        log_import_summary(result)
        @last_import_result = result
        result
      end

      def self.records_from_response(payload)
        if payload.is_a?(Hash)
          return payload["data"] if payload["data"].is_a?(Array)

          Rails.logger.error "Unsupported terminals payload data shape (TerminalsImporter): #{payload['data'].class}"
          nil
        elsif payload.is_a?(Array)
          payload
        else
          Rails.logger.error "Unsupported terminals payload shape (TerminalsImporter): #{payload.class}"
          nil
        end
      end

      def self.fetch_api_data
        uri = URI(API_URL)
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
          Rails.logger.error "Redirected (TerminalsImporter): #{API_URL} -> #{response['location']}"
          nil
        else
          Rails.logger.error "HTTP Error (TerminalsImporter): #{response.code} #{response.message} at #{API_URL} - Body: #{response.body.to_s[0..200]}"
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "JSON Parsing Error (TerminalsImporter): #{e.message} at #{API_URL}"
        nil
      rescue => e
        Rails.logger.error "Network Error (TerminalsImporter): #{e.message} at #{API_URL}"
        nil
      end

      def self.import_terminal(terminal_data, result = ImportResult.new)
        return skip_record(result, terminal_data, :row_not_object, "row is not an object") unless terminal_data.is_a?(Hash)

        api_id = integer_or_nil(terminal_data["id"])
        return skip_record(result, terminal_data, :missing_api_id, "missing id/api_id") unless api_id
        return skip_record(result, terminal_data, :missing_name, "missing name") if terminal_data["name"].blank?

        terminal = find_or_initialize_terminal(terminal_data, api_id)
        terminal.assign_attributes(terminal_attributes(terminal_data))
        terminal.location_name = determine_location_name(terminal_data, result)

        debug_pyro_gateway(terminal_data, terminal.location_name)

        if terminal.save
          result.imported += 1
          true
        else
          result.failed += 1
          result.validation_failed += 1
          add_sample(result, :failed, terminal_data, "validation failed: #{terminal.errors.full_messages.join(', ')}")
          false
        end
      rescue AmbiguousIdentityError => e
        skip_record(result, terminal_data, :ambiguous_identity, e.reason)
      rescue AmbiguousLocationError => e
        skip_record(result, terminal_data, :ambiguous_location, e.reason)
      rescue ActiveRecord::RecordNotUnique => e
        result.failed += 1
        result.duplicate_identity_conflicts += 1
        add_sample(result, :failed, terminal_data, "duplicate identity conflict: #{e.message}")
        false
      rescue => e
        result.failed += 1
        add_sample(result, :failed, terminal_data, e.message)
        false
      end

      def self.find_or_initialize_terminal(terminal_data, api_id = integer_or_nil(terminal_data["id"]))
        terminal = Terminal.find_by(api_id: api_id)
        return terminal if terminal

        # With a real API identity present, only attach to legacy rows that do not
        # already have a different API identity. Distinct gateway terminals often
        # share human-ish names/codes, so never collapse onto a populated api_id.
        legacy_terminal = find_legacy_terminal(terminal_data, allow_populated_api_id: false)
        return legacy_terminal if legacy_terminal

        Terminal.new(api_id: api_id)
      end

      def self.find_legacy_terminal(terminal_data, allow_populated_api_id: true)
        code = terminal_data["code"].presence
        if code
          by_code = Terminal.where(code: code)
          by_code = by_code.where(api_id: nil) unless allow_populated_api_id
          return by_code.first if by_code.one?
          raise AmbiguousIdentityError, "ambiguous code #{code.inspect}" if by_code.many?
        end

        name = terminal_data["name"].presence
        return unless name

        by_name = Terminal.where(name: name)
        by_name = by_name.where(api_id: nil) unless allow_populated_api_id
        return by_name.first if by_name.one?
        raise AmbiguousIdentityError, "ambiguous name #{name.inspect}" if by_name.many?
      end

      def self.terminal_attributes(terminal_data)
        TERMINAL_MAPPINGS.each_with_object({}) do |(payload_key, attribute), attributes|
          next unless Terminal.column_names.include?(attribute)

          value = terminal_data[payload_key]
          value = integer_or_nil(value) if integer_column?(attribute)
          attributes[attribute] = value
        end
      end

      def self.determine_location_name(data, result = nil)
        location = find_matching_location(data)
        return location.name if location

        fallback = location_name_candidates(data).first
        if fallback.present?
          result.fallback_location += 1 if result
          add_sample(result, :fallback_location, data, "no matching Location; using #{fallback.inspect}") if result
          return fallback
        end

        result.missing_location += 1 if result
        nil
      end

      def self.find_matching_location(data)
        find_location_by_api_id(data) || find_location_by_name(data) || find_location_by_code(data)
      end

      def self.find_location_by_api_id(data)
        location_api_id_candidates(data).each do |api_id, classification, id_column|
          location = find_location_for_api_candidate(api_id, classification, id_column)
          return location if location
        end

        nil
      end

      def self.find_location_for_api_candidate(api_id, classification, id_column)
        matches = Location.where(api_id: api_id, classification: classification).to_a

        if matches.empty? && Location.column_names.include?(id_column)
          matches = Location.where(id_column => api_id, classification: classification).to_a
        end

        disambiguate_locations(matches)
      end

      def self.find_location_by_name(data)
        location_name_candidates(data).each do |name|
          matches = Location.where("LOWER(name) = ?", name.downcase).to_a
          matches.concat(parenthesized_location_matches(name, data)) if matches.empty?

          location = disambiguate_locations(matches, data)
          return location if location
        end

        nil
      end

      def self.parenthesized_location_matches(name, data)
        star_system_name = data["star_system_name"].presence
        return [] if star_system_name.blank? || name.include?("(")

        Location.where("LOWER(name) = ?", "#{name} (#{star_system_name})".downcase).to_a
      end

      def self.find_location_by_code(data)
        code = data["location_code"].presence || data["code"].to_s.split("-").first.presence
        return if code.blank?

        disambiguate_locations(Location.where("LOWER(code) = ?", code.downcase).to_a, data)
      end

      def self.disambiguate_locations(matches, data = nil)
        matches = matches.compact.uniq
        return if matches.empty?
        return matches.first if matches.one?

        narrowed = narrow_locations_by_context(matches, data)
        return narrowed.first if narrowed.one?

        candidate_summary = matches.map { |location| "#{location.id}:#{location.name}" }.join(", ")
        raise AmbiguousLocationError, "ambiguous Location match among #{candidate_summary}"
      end

      def self.narrow_locations_by_context(matches, data)
        return matches unless data

        candidates = matches
        %w[star_system_name planet_name moon_name parent_name].each do |attribute|
          value = data[attribute].presence
          next unless value

          narrowed = candidates.select { |location| location.public_send(attribute).to_s.casecmp?(value) }
          candidates = narrowed if narrowed.any?
        end

        candidates
      end

      def self.location_name_candidates(data)
        LOCATION_NAME_KEYS.flat_map do |key|
          name = data[key].presence
          next [] unless name

          candidates = [name]
          star_system_name = data["star_system_name"].presence
          candidates << "#{name} (#{star_system_name})" if star_system_name.present? && !name.include?("(")
          candidates
        end.uniq
      end

      def self.location_api_id_candidates(data)
        LOCATION_API_ID_CANDIDATES.filter_map do |key, classification|
          api_id = integer_or_nil(data[key])
          [api_id, classification, key] if api_id&.positive?
        end
      end

      def self.integer_column?(attribute)
        Terminal.columns_hash[attribute]&.type == :integer
      end

      def self.integer_or_nil(value)
        return if value.blank?

        value.to_i
      end

      def self.skip_record(result, terminal_data, counter, reason)
        result.skipped += 1
        result.public_send("#{counter}=", result.public_send(counter) + 1) if result.respond_to?(counter)
        add_sample(result, :skipped, terminal_data, reason)
        false
      end

      def self.add_sample(result, bucket, terminal_data, reason)
        return unless result
        return if result.samples[bucket].size >= SAMPLE_LIMIT

        result.samples[bucket] << sample_for(terminal_data, reason)
      end

      def self.sample_for(terminal_data, reason)
        return { reason: reason, row: terminal_data.inspect } unless terminal_data.is_a?(Hash)

        terminal_data.slice(
          "id",
          "code",
          "name",
          "nickname",
          "terminal_name",
          "space_station_name",
          "city_name",
          "outpost_name",
          "poi_name",
          "moon_name",
          "planet_name",
          "star_system_name",
          "id_space_station",
          "id_city",
          "id_outpost",
          "id_poi",
          "id_moon",
          "id_planet",
          "id_star_system"
        ).merge(reason: reason)
      end

      def self.log_import_summary(result)
        Rails.logger.info result.log_line
        result.samples.each do |bucket, samples|
          Rails.logger.info "TerminalsImporter #{bucket} samples: #{samples.inspect}" if samples.any?
        end
      end

      def self.debug_pyro_gateway(terminal_data, resolved_location_name)
        fields = %w[
          name
          nickname
          code
          space_station_name
          city_name
          outpost_name
          poi_name
          moon_name
          planet_name
          star_system_name
        ]

        values = fields.map { |key| terminal_data[key] }.compact
        values << resolved_location_name
        return unless values.any? { |value| value.to_s.downcase.include?("pyro gateway") }

        Rails.logger.info "TerminalsImporter Pyro Gateway diagnostic: #{sample_for(terminal_data, "resolved_location_name=#{resolved_location_name.inspect}").inspect}"
      end
    end
  end
end
