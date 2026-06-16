require "test_helper"

module Admin
  module Data
    class StarbitizenShipImporterTest < ActiveSupport::TestCase
      test "updates matching ship from the most complete duplicate starbitizen record" do
        ship = Ship.create!(
          model: "F7A Hornet Mk II",
          name: "F7A Hornet Mk II",
          length: 28,
          msrp: 999,
          fuel_quantum: 0,
          qnt_fuel_capacity: 0,
          hp: 45,
          ship_image_primary: "F7A_Hornet_Mk_II_Profile_28m.png",
          company_name: "Old Manufacturer"
        )

        payload = [
          {
            "shipname" => "F7A Hornet Mk II",
            "manufacturer" => "Anvil",
            "cargocapacity" => "0",
            "requiresdocking" => "false",
            "filename" => "F7A_Profile_22_5m.png",
            "keel" => "23",
            "msrp" => "2300",
            "qfuel" => "583",
            "hp" => "23",
            "category" => "ship",
            "isactive" => "1"
          },
          {
            "shipname" => "F7A Hornet Mk II",
            "manufacturer" => "Anvil",
            "cargocapacity" => "0",
            "requiresdocking" => "false",
            "filename" => "F7A_Hornet_Mk_II_Profile_28m.png",
            "keel" => "28",
            "msrp" => "",
            "qfuel" => "0.0",
            "hp" => "45",
            "category" => "ship",
            "isactive" => "1"
          }
        ]

        result = StarbitizenShipImporter.import_payload(payload)

        assert_equal 1, result.updated_count
        assert_equal 0, result.failed_count
        assert_equal 1, result.duplicate_count
        assert_includes result.duplicate_shipnames, "F7A Hornet Mk II"

        ship.reload
        assert_equal 0, ship.scu
        assert_equal 23, ship.length
        assert_equal 2300, ship.msrp
        assert_equal 583, ship.fuel_quantum
        assert_equal 583, ship.qnt_fuel_capacity
        assert_equal 23, ship.hp
        assert_equal false, ship.is_docking
        assert_equal "Anvil", ship.company_name
        assert_equal "F7A_Profile_22_5m.png", ship.ship_image_primary
      end

      test "reports failed updates with validation errors" do
        ship = Ship.create!(model: "Invalid Existing Ship", name: "Invalid Existing Ship", length: 10)
        Ship.where(id: ship.id).update_all(model: "")

        result = StarbitizenShipImporter.import_payload([
          {
            "shipname" => "Invalid Existing Ship",
            "keel" => "20",
            "msrp" => "100",
            "qfuel" => "50",
            "hp" => "5"
          }
        ])

        assert_equal 0, result.updated_count
        assert_equal 1, result.failed_count
        assert_match "Invalid Existing Ship", result.message
        assert_match "Model can't be blank", result.message
        assert_equal 10, ship.reload.length
      end

      test "blank numeric values from a single selected record are saved as nil" do
        ship = Ship.create!(
          model: "Blank Numeric Test",
          name: "Blank Numeric Test",
          length: 10,
          msrp: 100,
          fuel_quantum: 50,
          qnt_fuel_capacity: 50,
          hp: 5
        )

        result = StarbitizenShipImporter.import_payload([
          {
            "shipname" => "Blank Numeric Test",
            "keel" => "",
            "msrp" => "",
            "qfuel" => "",
            "hp" => ""
          }
        ])

        assert_equal 1, result.updated_count
        ship.reload
        assert_nil ship.length
        assert_nil ship.msrp
        assert_nil ship.fuel_quantum
        assert_nil ship.qnt_fuel_capacity
        assert_nil ship.hp
      end

      test "reports ships not found" do
        result = StarbitizenShipImporter.import_payload([
          { "shipname" => "Missing Ship", "keel" => "20" }
        ])

        assert_equal 0, result.updated_count
        assert_equal ["Missing Ship"], result.not_found_ships
        assert_match "Could not find: Missing Ship", result.message
      end
    end
  end
end
