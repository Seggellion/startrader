require "test_helper"

module Admin
  module Data
    class TerminalsImporterTest < ActiveSupport::TestCase
      setup do
        Terminal.delete_all
        Location.delete_all

        @city = Location.create!(
          name: "Lorville",
          classification: "city",
          api_id: 200,
          code: "LOR"
        )
        @station = Location.create!(
          name: "Everus Harbor",
          classification: "space_station",
          api_id: 300,
          code: "EVH"
        )
      end

      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [terminal_payload])

        assert_difference -> { Terminal.count }, 1 do
          assert_equal 1, TerminalsImporter.import_raw_json!(json).to_i
        end

        terminal = Terminal.find_by!(api_id: 7001)
        assert_equal "Admin - Lorville", terminal.name
        assert_equal "LOR-Admin", terminal.code
        assert_equal "Lorville Admin", terminal.nickname
        assert_equal 1, terminal.id_star_system
        assert_equal 2, terminal.id_planet
        assert_equal 3, terminal.id_orbit
        assert_equal 4, terminal.id_moon
        assert_equal 300, terminal.id_space_station
        assert_equal 200, terminal.id_city
        assert_equal 5, terminal.id_outpost
        assert_equal 6, terminal.id_poi
        assert_equal 7, terminal.id_faction
        assert_equal 8, terminal.id_company
        assert_equal 32, terminal.max_container_size
        assert_equal @station.name, terminal.location_name
        assert_equal @station, terminal.location
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([terminal_payload("id" => 7002, "code" => "LOR-Cargo")])

        assert_difference -> { Terminal.count }, 1 do
          assert_equal 1, TerminalsImporter.import_raw_json!(json).to_i
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { Terminal.count } do
          result = TerminalsImporter.import_raw_json!("{")
          assert_equal 0, result.to_i
          assert_equal 1, result.failed
        end
      end

      test "updates an existing terminal matched by api id without creating duplicates" do
        Terminal.create!(
          api_id: 7001,
          name: "Old Name",
          code: "OLD",
          location_name: @station.name
        )

        assert_no_difference -> { Terminal.count } do
          assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([terminal_payload("name" => "Updated Name")])).to_i
        end

        terminal = Terminal.find_by!(api_id: 7001)
        assert_equal "Updated Name", terminal.name
        assert_equal "LOR-Admin", terminal.code
        assert_equal @station.name, terminal.location_name
      end

      test "assigns api id from terminal data id" do
        assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([terminal_payload("id" => 7700)])).to_i

        assert Terminal.exists?(api_id: 7700)
      end

      test "updates a legacy terminal matched by unique code" do
        legacy = Terminal.create!(name: "Legacy Terminal", code: "LOR-Admin")

        assert_no_difference -> { Terminal.count } do
          assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([terminal_payload("name" => "Modern Terminal")])).to_i
        end

        assert_equal legacy.id, Terminal.find_by!(api_id: 7001).id
        assert_equal "Modern Terminal", legacy.reload.name
      end

      test "location name resolves by relevant api id when name is missing" do
        payload = terminal_payload("city_name" => nil, "space_station_name" => nil)

        assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([payload])).to_i

        assert_equal @station.name, Terminal.find_by!(api_id: 7001).location_name
      end

      test "fallback location name is used and warning is logged when no location exists" do
        payload = terminal_payload("id" => 7003, "city_name" => "Unknown Landing Zone", "id_city" => 999)

        result = TerminalsImporter.import_raw_json!(JSON.generate([payload]))

        assert_equal 1, result.to_i
        assert_equal 1, result.fallback_location
        assert_equal "Unknown Landing Zone", Terminal.find_by!(api_id: 7003).location_name
        assert result.samples[:fallback_location].any? { |sample| sample[:reason].include?("no matching Location") }
      end

      test "raw json import creates two pyro gateway terminals with distinct api ids" do
        stanton_gateway = Location.create!(
          name: "Pyro Gateway (Stanton)",
          classification: "space_station",
          api_id: 8001,
          star_system_name: "Stanton"
        )
        nyx_gateway = Location.create!(
          name: "Pyro Gateway (Nyx)",
          classification: "space_station",
          api_id: 8002,
          star_system_name: "Nyx"
        )

        payloads = [
          pyro_gateway_payload(id: 9001, location_api_id: stanton_gateway.api_id, star_system_name: "Stanton"),
          pyro_gateway_payload(id: 9002, location_api_id: nyx_gateway.api_id, star_system_name: "Nyx")
        ]

        assert_difference -> { Terminal.count }, 2 do
          assert_equal 2, TerminalsImporter.import_raw_json!(JSON.generate(payloads)).to_i
        end

        assert_equal stanton_gateway.name, Terminal.find_by!(api_id: 9001).location_name
        assert_equal nyx_gateway.name, Terminal.find_by!(api_id: 9002).location_name
      end

      test "location matching resolves similar gateway names by star system suffix" do
        stanton_gateway = Location.create!(
          name: "Pyro Gateway (Stanton)",
          classification: "space_station",
          api_id: 8001,
          star_system_name: "Stanton"
        )
        Location.create!(
          name: "Pyro Gateway (Nyx)",
          classification: "space_station",
          api_id: 8002,
          star_system_name: "Nyx"
        )

        payload = pyro_gateway_payload(id: 9003, location_api_id: nil, star_system_name: "Stanton")

        assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([payload])).to_i
        assert_equal stanton_gateway.name, Terminal.find_by!(api_id: 9003).location_name
      end

      test "location matching prefers api id fields over misleading name fields" do
        stanton_gateway = Location.create!(
          name: "Pyro Gateway (Stanton)",
          classification: "space_station",
          api_id: 8001,
          star_system_name: "Stanton"
        )
        Location.create!(
          name: "Pyro Gateway (Nyx)",
          classification: "space_station",
          api_id: 8002,
          star_system_name: "Nyx"
        )

        payload = pyro_gateway_payload(
          id: 9004,
          location_api_id: stanton_gateway.api_id,
          star_system_name: "Nyx"
        )

        assert_equal 1, TerminalsImporter.import_raw_json!(JSON.generate([payload])).to_i
        assert_equal stanton_gateway.name, Terminal.find_by!(api_id: 9004).location_name
      end

      test "ambiguous legacy fallback does not overwrite unrelated terminals" do
        Terminal.create!(name: "Legacy One", code: "PYR-GW")
        Terminal.create!(name: "Legacy Two", code: "PYR-GW")
        payload = pyro_gateway_payload(id: 9005, code: "PYR-GW")

        result = nil
        assert_no_difference -> { Terminal.count } do
          result = TerminalsImporter.import_raw_json!(JSON.generate([payload]))
        end

        assert_equal 0, result.to_i
        assert_equal 1, result.skipped
        assert_equal 1, result.ambiguous_identity
        refute Terminal.exists?(api_id: 9005)
      end

      test "summary counts missing api id and missing name skips" do
        result = TerminalsImporter.import_raw_json!(JSON.generate([
          terminal_payload("id" => nil),
          terminal_payload("id" => 7004, "name" => nil)
        ]))

        assert_equal 0, result.to_i
        assert_equal 2, result.skipped
        assert_equal 1, result.missing_api_id
        assert_equal 1, result.missing_name
        assert_equal 2, result.samples[:skipped].size
      end

      private

      def terminal_payload(overrides = {})
        {
          "id" => 7001,
          "code" => "LOR-Admin",
          "name" => "Admin - Lorville",
          "nickname" => "Lorville Admin",
          "id_star_system" => 1,
          "id_planet" => 2,
          "id_orbit" => 3,
          "id_moon" => 4,
          "id_space_station" => 300,
          "id_city" => 200,
          "id_outpost" => 5,
          "id_poi" => 6,
          "id_faction" => 7,
          "id_company" => 8,
          "max_container_size" => 32,
          "space_station_name" => nil,
          "city_name" => @city.name,
          "outpost_name" => nil,
          "poi_name" => nil,
          "moon_name" => nil,
          "planet_name" => nil,
          "star_system_name" => "Stanton"
        }.merge(overrides)
      end

      def pyro_gateway_payload(id:, location_api_id:, star_system_name:, code: nil)
        {
          "id" => id,
          "code" => code || "PYR-GW-#{star_system_name}",
          "name" => "Pyro Gateway Admin",
          "nickname" => "Pyro Gateway #{star_system_name}",
          "id_star_system" => star_system_name == "Stanton" ? 1 : 2,
          "id_space_station" => location_api_id,
          "space_station_name" => "Pyro Gateway",
          "star_system_name" => star_system_name,
          "max_container_size" => 32
        }
      end
    end
  end
end
