require "test_helper"

module Admin
  module Data
    class CommoditiesImporterTest < ActiveSupport::TestCase
      setup do
        StarBitizenRun.delete_all
        UserShipCargo.delete_all
        ProductionFacility.delete_all
        Commodity.delete_all
      end

      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [commodity_payload])

        assert_difference -> { Commodity.count }, 1 do
          assert_equal 1, CommoditiesImporter.import_raw_json!(json)
        end

        commodity = Commodity.find_by!(api_id: 501)
        assert_equal "Agricium", commodity.name
        assert_equal "AGRI", commodity.code
        assert_equal "mineral", commodity.kind
        assert_equal 0.5, commodity.weight_scu
        assert_equal 12.34, commodity.price_buy.to_f
        assert_equal 23.45, commodity.price_sell.to_f
        assert_equal 123, commodity.id_parent
        assert_equal "https://example.test/agricium", commodity.wiki
        assert_equal 1_700_000_000, commodity.date_added
        assert_equal 1_700_000_001, commodity.date_modified
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([commodity_payload("id" => 502, "code" => "BEXA", "name" => "Bexalite")])

        assert_difference -> { Commodity.count }, 1 do
          assert_equal 1, CommoditiesImporter.import_raw_json!(json)
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { Commodity.count } do
          assert_equal 0, CommoditiesImporter.import_raw_json!("{")
        end
      end

      test "creates a new commodity and assigns api id from payload id" do
        assert_equal 1, CommoditiesImporter.import_raw_json!(JSON.generate([commodity_payload("id" => 777)]))

        assert Commodity.exists?(api_id: 777)
      end

      test "updates existing commodity matched by api id without creating duplicates" do
        Commodity.create!(
          api_id: 501,
          name: "Old Name",
          code: "OLD",
          is_available: false
        )

        assert_no_difference -> { Commodity.count } do
          assert_equal 1, CommoditiesImporter.import_raw_json!(JSON.generate([commodity_payload("name" => "Updated Agricium")]))
        end

        commodity = Commodity.find_by!(api_id: 501)
        assert_equal "Updated Agricium", commodity.name
        assert_equal "AGRI", commodity.code
        assert commodity.is_available
      end

      test "updates legacy commodity matched by unique code" do
        legacy = Commodity.create!(name: "Legacy Agricium", code: "AGRI")

        assert_no_difference -> { Commodity.count } do
          assert_equal 1, CommoditiesImporter.import_raw_json!(JSON.generate([commodity_payload]))
        end

        assert_equal legacy.id, Commodity.find_by!(api_id: 501).id
        assert_equal "Agricium", legacy.reload.name
      end

      test "ambiguous legacy matches do not create duplicates" do
        Commodity.create!(name: "Legacy One", code: "AGRI")
        Commodity.create!(name: "Legacy Two", code: "AGRI")

        assert_no_difference -> { Commodity.count } do
          assert_equal 0, CommoditiesImporter.import_raw_json!(JSON.generate([commodity_payload]))
        end

        refute Commodity.exists?(api_id: 501)
      end

      test "boolean fields are cast from common api values" do
        payloads = [
          commodity_payload("id" => 601, "code" => "BOOL1", "name" => "Bool One", "is_available" => 1, "is_visible" => "true", "is_buyable" => true, "is_sellable" => "1", "is_illegal" => false),
          commodity_payload("id" => 602, "code" => "BOOL2", "name" => "Bool Two", "is_available" => 0, "is_visible" => "false", "is_buyable" => false, "is_sellable" => "0", "is_illegal" => "true")
        ]

        assert_equal 2, CommoditiesImporter.import_raw_json!(JSON.generate(payloads))

        first = Commodity.find_by!(api_id: 601)
        second = Commodity.find_by!(api_id: 602)

        assert first.is_available
        assert first.is_visible
        assert first.is_buyable
        assert first.is_sellable
        refute first.is_illegal
        refute second.is_available
        refute second.is_visible
        refute second.is_buyable
        refute second.is_sellable
        assert second.is_illegal
      end

      test "import all still works with a data wrapped payload" do
        CommoditiesImporter.stub :fetch_api_data, { "data" => [commodity_payload("id" => 701)] } do
          assert_equal 1, CommoditiesImporter.import_all!
        end

        assert Commodity.exists?(api_id: 701)
      end

      test "import single still works" do
        CommoditiesImporter.stub :fetch_api_data, { "data" => [commodity_payload("id" => 702)] } do
          assert_equal true, CommoditiesImporter.import_single!
        end

        assert Commodity.exists?(api_id: 702)
      end

      private

      def commodity_payload(overrides = {})
        {
          "id" => 501,
          "id_parent" => 123,
          "name" => "Agricium",
          "code" => "AGRI",
          "kind" => "mineral",
          "weight_scu" => 0.5,
          "price_buy" => "12.34",
          "price_sell" => "23.45",
          "is_available" => 1,
          "is_available_live" => "true",
          "is_visible" => true,
          "is_mineral" => 1,
          "is_raw" => "1",
          "is_refined" => 0,
          "is_harvestable" => "false",
          "is_buyable" => "true",
          "is_sellable" => "1",
          "is_temporary" => false,
          "is_illegal" => "false",
          "is_fuel" => 0,
          "wiki" => "https://example.test/agricium",
          "date_added" => 1_700_000_000,
          "date_modified" => 1_700_000_001
        }.merge(overrides)
      end
    end
  end
end
