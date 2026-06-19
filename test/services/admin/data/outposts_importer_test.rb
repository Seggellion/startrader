require "test_helper"

module Admin
  module Data
    class OutpostsImporterTest < ActiveSupport::TestCase
      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [outpost_payload("Raw Wrapped Outpost")])

        assert_difference -> { Location.where(classification: "outpost").count }, 1 do
          assert_equal 1, OutpostsImporter.import_raw_json!(json)
        end

        outpost = Location.find_by!(name: "Raw Wrapped Outpost")
        assert_equal "outpost", outpost.classification
        assert_equal true, outpost.has_trade_terminal
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([outpost_payload("Raw Array Outpost")])

        assert_difference -> { Location.where(classification: "outpost").count }, 1 do
          assert_equal 1, OutpostsImporter.import_raw_json!(json)
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { Location.count } do
          assert_equal 0, OutpostsImporter.import_raw_json!("{")
        end
      end

      private

      def outpost_payload(name)
        {
          "id" => rand(10_000..99_999),
          "name" => name,
          "nickname" => "#{name} Nick",
          "code" => "ROP",
          "type" => "landing_zone",
          "mass" => 100,
          "periapsis" => 20,
          "apoapsis" => 30,
          "id_star_system" => 1,
          "id_planet" => 2,
          "id_orbit" => 0,
          "id_moon" => 3,
          "id_space_station" => 0,
          "id_outpost" => 4,
          "id_poi" => 0,
          "id_city" => 0,
          "id_faction" => 0,
          "id_company" => 0,
          "is_available" => 1,
          "is_available_live" => 1,
          "is_visible" => 1,
          "is_default_system" => 0,
          "is_affinity_influenceable" => 0,
          "is_habitation" => 1,
          "is_refinery" => 0,
          "is_cargo_center" => 1,
          "is_medical" => 0,
          "is_food" => 1,
          "is_shop_fps" => 0,
          "is_shop_vehicle" => 0,
          "is_refuel" => 1,
          "is_repair" => 1,
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
          "outpost_name" => name,
          "city_name" => nil,
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
