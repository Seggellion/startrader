require "test_helper"

module Admin
  module Data
    class StarSystemsImporterTest < ActiveSupport::TestCase
      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [star_system_payload("Wrapped System", 81_001)])

        assert_difference -> { Location.where(classification: "star_system").count }, 1 do
          assert_equal 1, StarSystemsImporter.import_raw_json!(json)
        end

        star_system = Location.find_by!(api_id: 81_001, classification: "star_system")
        assert_equal "Wrapped System", star_system.name
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([star_system_payload("Array System", 81_002)])

        assert_difference -> { Location.where(classification: "star_system").count }, 1 do
          assert_equal 1, StarSystemsImporter.import_raw_json!(json)
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { Location.count } do
          assert_equal 0, StarSystemsImporter.import_raw_json!("{")
        end
      end

      test "unexpected raw json format returns zero" do
        assert_no_difference -> { Location.count } do
          assert_equal 0, StarSystemsImporter.import_raw_json!(JSON.generate("data" => { "id" => 81_003 }))
        end
      end

      test "import location updates existing star system by api id and classification" do
        existing = Location.create!(
          api_id: 81_004,
          classification: "star_system",
          name: "Old System Name",
          code: "OLD",
          is_available: false,
          is_available_live: false,
          is_visible: false,
          is_default_system: false,
          is_affinity_influenceable: false
        )

        assert_no_difference -> { Location.where(classification: "star_system").count } do
          assert_equal true, StarSystemsImporter.import_location(star_system_payload("New System Name", 81_004))
        end

        existing.reload
        assert_equal "New System Name", existing.name
        assert_equal "SYS", existing.code
        assert_nil existing.parent_name
      end

      test "import location updates changed fields from the json source" do
        StarSystemsImporter.import_location(star_system_payload("Original System", 81_005, "code" => "ORG"))

        assert_equal true, StarSystemsImporter.import_location(
          star_system_payload(
            "Updated System",
            81_005,
            "code" => "UPD",
            "nickname" => "Updated Nick",
            "is_default" => 0,
            "is_visible" => 0
          )
        )

        star_system = Location.find_by!(api_id: 81_005, classification: "star_system")
        assert_equal "Updated System", star_system.name
        assert_equal "Updated Nick", star_system.nickname
        assert_equal "UPD", star_system.code
        assert_equal false, star_system.is_default_system
        assert_equal false, star_system.is_visible
      end

      test "missing optional boolean keys do not crash import location" do
        payload = star_system_payload("Sparse System", 81_006)
        payload.delete_if { |key, _value| key.start_with?("is_") || key.start_with?("has_") }

        assert_equal true, StarSystemsImporter.import_location(payload)

        star_system = Location.find_by!(api_id: 81_006, classification: "star_system")
        assert_equal false, star_system.is_available
        assert_equal false, star_system.is_default_system
        assert_equal false, star_system.has_freight_elevator
      end

      private

      def star_system_payload(name, api_id, overrides = {})
        {
          "id" => api_id,
          "name" => name,
          "nickname" => "#{name} Nick",
          "code" => "SYS",
          "type" => "star_system",
          "id_star_system" => api_id,
          "id_planet" => 0,
          "id_orbit" => 0,
          "id_moon" => 0,
          "id_space_station" => 0,
          "id_outpost" => 0,
          "id_poi" => 0,
          "id_city" => 0,
          "id_faction" => 0,
          "id_company" => 0,
          "is_available" => 1,
          "is_available_live" => 1,
          "is_visible" => 1,
          "is_default" => 1,
          "is_affinity_influenceable" => 1,
          "is_habitation" => 0,
          "is_refinery" => 0,
          "is_cargo_center" => 0,
          "is_medical" => 0,
          "is_food" => 0,
          "is_shop_fps" => 0,
          "is_shop_vehicle" => 0,
          "is_refuel" => 0,
          "is_repair" => 0,
          "is_nqa" => 0,
          "is_player_owned" => 0,
          "is_auto_load" => 0,
          "has_loading_dock" => 0,
          "has_docking_port" => 0,
          "has_freight_elevator" => 0,
          "star_system_name" => name,
          "planet_name" => nil,
          "orbit_name" => nil,
          "moon_name" => nil,
          "space_station_name" => nil,
          "outpost_name" => nil,
          "city_name" => nil,
          "faction_name" => nil,
          "company_name" => nil,
          "max_container_size" => 0,
          "date_added" => 1_700_000_000,
          "date_modified" => 1_700_000_001
        }.merge(overrides)
      end
    end
  end
end
