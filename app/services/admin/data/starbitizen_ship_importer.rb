module Admin
  module Data
    class StarbitizenShipImporter
      Result = Struct.new(
        :updated_count,
        :failed_updates,
        :not_found_ships,
        :duplicate_count,
        :duplicate_shipnames,
        keyword_init: true
      ) do
        def failed_count
          failed_updates.size
        end

        def message
          parts = [
            "Successfully updated #{updated_count} ships.",
            "Failed #{failed_count} ships.",
            "Skipped #{duplicate_count} duplicate JSON records."
          ]

          parts << "Duplicate shipnames: #{duplicate_shipnames.join(', ')}." if duplicate_shipnames.any?
          parts << "Could not find: #{not_found_ships.join(', ')}." if not_found_ships.any?

          if failed_updates.any?
            failures = failed_updates.map { |failure| "#{failure[:shipname]} (#{failure[:errors]})" }
            parts << "Failed updates: #{failures.join('; ')}."
          end

          parts.join(" ")
        end
      end

      PRIORITY_FIELDS = %w[msrp qfuel keel hp filename].freeze
      SECONDARY_FIELDS = %w[cargocapacity requiresdocking manufacturer category isactive].freeze

      class << self
        def import_raw_json!(json_string)
          raw_payload = JSON.parse(json_string)
          import_payload(raw_payload)
        end

        def import_payload(raw_payload)
          payload = records_from(raw_payload)
          selected_records, duplicate_count, duplicate_shipnames = select_best_records(payload)

          updated_count = 0
          failed_updates = []
          not_found_ships = []

          selected_records.each_value do |entry|
            data = entry[:data]
            shipname = normalized_string(data["shipname"])
            ship = Ship.where("lower(name) = ?", shipname.downcase).first

            if ship
              begin
                ship.assign_attributes(attributes_for(data))
                ship.save!
                updated_count += 1
              rescue ActiveRecord::RecordInvalid => e
                failed_updates << {
                  shipname: shipname,
                  errors: e.record.errors.full_messages.to_sentence
                }
              rescue ActiveRecord::ActiveRecordError => e
                failed_updates << {
                  shipname: shipname,
                  errors: e.message
                }
              end
            else
              not_found_ships << shipname.presence || "(blank shipname)"
            end
          end

          Result.new(
            updated_count: updated_count,
            failed_updates: failed_updates,
            not_found_ships: not_found_ships,
            duplicate_count: duplicate_count,
            duplicate_shipnames: duplicate_shipnames
          )
        end

        private

        def records_from(raw_payload)
          payload = raw_payload.is_a?(Hash) && raw_payload.key?("data") ? raw_payload["data"] : raw_payload
          Array.wrap(payload).select { |record| record.is_a?(Hash) }
        end

        def select_best_records(payload)
          selected_records = {}
          duplicate_count = 0
          duplicate_shipnames = []

          payload.each_with_index do |data, index|
            shipname = normalized_string(data["shipname"])
            key = shipname.downcase
            entry = {
              data: data,
              index: index,
              score: completeness_score(data)
            }

            if selected_records.key?(key)
              duplicate_count += 1
              duplicate_shipnames << shipname unless duplicate_shipnames.include?(shipname)
              selected_records[key] = entry if better_record?(entry, selected_records[key])
            else
              selected_records[key] = entry
            end
          end

          [selected_records, duplicate_count, duplicate_shipnames]
        end

        def better_record?(candidate, current)
          return true if candidate[:score] > current[:score]

          candidate[:score] == current[:score] && candidate[:index] > current[:index]
        end

        def completeness_score(data)
          priority_score = PRIORITY_FIELDS.sum { |field| present_value?(data[field]) ? 2 : 0 }
          secondary_score = SECONDARY_FIELDS.count { |field| present_value?(data[field]) }

          priority_score + secondary_score
        end

        def attributes_for(data)
          attributes = {
            scu: integer_value(data["cargocapacity"]),
            length: integer_value(data["keel"]),
            msrp: integer_value(data["msrp"]),
            hp: integer_value(data["hp"]),
            is_docking: boolean_value(data["requiresdocking"]),
            fuel_quantum: float_value(data["qfuel"]),
            qnt_fuel_capacity: float_value(data["qfuel"]),
            company_name: normalized_optional_value(data["manufacturer"]),
            ship_image_primary: normalized_optional_value(data["filename"])
          }

          attributes[:manufacturer] = normalized_optional_value(data["manufacturer"])
          attributes[:filename] = normalized_optional_value(data["filename"])
          attributes[:category] = normalized_optional_value(data["category"])
          attributes[:isactive] = boolean_value(data["isactive"])

          attributes.slice(*Ship.column_names.map(&:to_sym))
        end

        def integer_value(value)
          return nil unless present_value?(value)

          value
        end

        def float_value(value)
          return nil unless present_value?(value)

          value
        end

        def boolean_value(value)
          ActiveModel::Type::Boolean.new.cast(value).presence || false
        end

        def normalized_optional_value(value)
          return nil unless present_value?(value)

          value.to_s.strip
        end

        def normalized_string(value)
          value.to_s.strip
        end

        def present_value?(value)
          !value.nil? && value.to_s.strip.present?
        end
      end
    end
  end
end
