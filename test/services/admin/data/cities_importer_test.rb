require "test_helper"

module Admin
  module Data
    class CitiesImporterTest < ActiveSupport::TestCase
      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [city_payload("Wrapped City", 91_001)])

        assert_difference -> { Location.where(classification: "city").count }, 1 do
          assert_equal 1, CitiesImporter.import_raw_json!(json)
        end

        city = Location.find_by!(api_id: 91_001, classification: "city")
        assert_equal "Wrapped City", city.name
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([city_payload("Array City", 91_002)])

        assert_difference -> { Location.where(classification: "city").count }, 1 do
          assert_equal 1, CitiesImporter.import_raw_json!(json)
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { Location.count } do
          assert_equal 0, CitiesImporter.import_raw_json!("{")
        end
      end

      test "import location updates existing city by api id and classification" do
        existing = Location.create!(
          api_id: 91_003,
          classification: "city",
          name: "Old City Name",
          is_refuel: false,
          is_repair: false,
          is_medical: false,
          is_habitation: false,
          is_default_system: false
        )

        assert_no_difference -> { Location.where(classification: "city").count } do
          assert_equal true, CitiesImporter.import_location(city_payload("New City Name", 91_003))
        end

        existing.reload
        assert_equal "New City Name", existing.name
        assert_equal "Arial", existing.parent_name
        assert_equal true, existing.is_refuel
        assert_equal true, existing.is_repair
        assert_equal true, existing.is_medical
        assert_equal true, existing.is_habitation
        assert_equal true, existing.is_default_system
      end

      test "import location supports internal boolean keys" do
        payload = city_payload("Internal Boolean City", 91_004)
        %w[has_refuel has_repair has_clinic has_habitation is_default].each do |key|
          payload.delete(key)
        end

        assert_equal true, CitiesImporter.import_location(
          payload.merge(
            "is_refuel" => 1,
            "is_repair" => 1,
            "is_medical" => 1,
            "is_habitation" => 1,
            "is_default_system" => 1
          )
        )

        city = Location.find_by!(api_id: 91_004, classification: "city")
        assert_equal true, city.is_refuel
        assert_equal true, city.is_repair
        assert_equal true, city.is_medical
        assert_equal true, city.is_habitation
        assert_equal true, city.is_default_system
      end

      private

      def city_payload(name, api_id)
        {
          "id" => api_id,
          "name" => name,
          "nickname" => "#{name} Nick",
          "code" => "CTY",
          "type" => "city",
          "mass" => 100,
          "periapsis" => 20,
          "apoapsis" => 30,
          "id_star_system" => 1,
          "id_planet" => 2,
          "id_orbit" => 0,
          "id_moon" => 3,
          "id_space_station" => 0,
          "id_outpost" => 0,
          "id_poi" => 0,
          "id_city" => 4,
          "id_faction" => 0,
          "id_company" => 0,
          "is_available" => 1,
          "is_available_live" => 1,
          "is_visible" => 1,
          "is_default" => 1,
          "is_affinity_influenceable" => 0,
          "has_habitation" => 1,
          "has_refinery" => 1,
          "has_cargo_center" => 1,
          "has_clinic" => 1,
          "has_food" => 1,
          "is_shop_fps" => 0,
          "is_shop_vehicle" => 0,
          "has_refuel" => 1,
          "has_repair" => 1,
          "is_nqa" => 0,
          "is_player_owned" => 0,
          "is_auto_load" => 0,
          "has_loading_dock" => 1,
          "has_docking_port" => 0,
          "has_freight_elevator" => 1,
          "has_trade_terminal" => 1,
          "star_system_name" => "Stanton",
          "planet_name" => "Hurston",
          "orbit_name" => nil,
          "moon_name" => "Arial",
          "space_station_name" => nil,
          "outpost_name" => nil,
          "city_name" => name,
          "faction_name" => nil,
          "company_name" => nil,
          "max_container_size" => 32,
          "date_added" => 1_700_000_000,
          "date_modified" => 1_700_000_001
        }
      end
    end
  end
end
