require "test_helper"

module Admin
  module Data
    class FacilitiesPopulatorTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @old_queue_adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :test
        clear_enqueued_jobs
        clear_performed_jobs

        ProductionFacility.delete_all
        Terminal.delete_all
        Location.delete_all
        Commodity.delete_all

        @location = Location.create!(
          name: "Lorville",
          classification: "city",
          star_system_name: "Stanton"
        )
        @terminal = Terminal.create!(
          api_id: 42,
          name: "Lorville CBD",
          location_name: @location.name
        )
        @commodity = Commodity.create!(name: "Agricium", api_id: 101, is_sellable: true)
      end

      teardown do
        clear_enqueued_jobs
        clear_performed_jobs
        ProductionFacility.suppress_market_broadcasts = false
        ActiveJob::Base.queue_adapter = @old_queue_adapter
      end

      test "imports raw json wrapped in a top-level data key" do
        json = JSON.generate("data" => [facility_payload])

        assert_difference -> { ProductionFacility.count }, 1 do
          assert_equal 1, FacilitiesPopulator.import_raw_json!(json)
        end

        facility = ProductionFacility.find_by!(api_id: 9001)
        assert_equal @terminal.api_id, facility.id_terminal
        assert_equal @location.name, facility.location_name
        assert_equal "Lorville CBD", facility.terminal_name
        assert_equal "Lorville CBD", facility.facility_name
        assert_equal @commodity.name, facility.commodity_name
        assert_equal @commodity.api_id, facility.id_commodity
        assert_equal 12.34, facility.price_buy.to_f
        assert_equal 10.11, facility.price_buy_avg.to_f
        assert_equal 23.45, facility.price_sell.to_f
        assert_equal 20.22, facility.price_sell_avg.to_f
        assert_equal 15, facility.scu_buy
        assert_equal 12, facility.scu_buy_avg
        assert_equal 75, facility.scu_sell_stock
        assert_equal 70, facility.scu_sell_stock_avg
        assert_equal 55, facility.scu_sell
        assert_equal 50, facility.scu_sell_avg
        assert_equal 1, facility.status_buy
        assert_equal 1, facility.status_sell
        assert_equal "1,2,4", facility.container_sizes
        assert_equal 1_700_000_000, facility.date_added
        assert_equal 1_700_000_001, facility.date_modified
        assert_equal 5, facility.production_rate
        assert_equal 5, facility.consumption_rate
        assert_equal 75, facility.inventory
        assert_equal 1_000, facility.max_inventory
      end

      test "imports raw json from a direct array" do
        json = JSON.generate([facility_payload("id" => 9002)])

        assert_difference -> { ProductionFacility.count }, 1 do
          assert_equal 1, FacilitiesPopulator.import_raw_json!(json)
        end
      end

      test "invalid raw json returns zero" do
        assert_no_difference -> { ProductionFacility.count } do
          assert_equal 0, FacilitiesPopulator.import_raw_json!("{")
        end
      end

      test "destructive replacement removes stale production facilities" do
        ProductionFacility.create!(
          api_id: 123,
          facility_name: "Stale Facility",
          production_rate: 1,
          consumption_rate: 0,
          inventory: 5,
          max_inventory: 10
        )

        assert_equal 1, FacilitiesPopulator.import_raw_json!(JSON.generate([facility_payload]))

        assert_nil ProductionFacility.find_by(api_id: 123)
        assert ProductionFacility.exists?(api_id: 9001)
      end

      test "skips rows when no matching terminal exists" do
        json = JSON.generate([facility_payload("id" => 9003, "id_terminal" => 999)])

        assert_no_difference -> { ProductionFacility.count } do
          assert_equal 0, FacilitiesPopulator.import_raw_json!(json)
        end
      end

      test "skips rows when terminal has no location" do
        Terminal.create!(api_id: 77, name: "Unlinked Terminal", location_name: "Missing")
        json = JSON.generate([facility_payload("id" => 9004, "id_terminal" => 77)])

        assert_no_difference -> { ProductionFacility.count } do
          assert_equal 0, FacilitiesPopulator.import_raw_json!(json)
        end
      end

      test "inventory is not nil on newly imported facilities" do
        assert_equal 1, FacilitiesPopulator.import_raw_json!(JSON.generate([facility_payload("scu_sell_stock" => nil)]))

        assert_equal 0, ProductionFacility.find_by!(api_id: 9001).inventory
      end

      test "api import path uses shared destructive import flow" do
        ProductionFacility.create!(
          api_id: 123,
          facility_name: "Stale Facility",
          production_rate: 1,
          consumption_rate: 0,
          inventory: 5,
          max_inventory: 10
        )

        FacilitiesPopulator.stub :fetch_api_data, { "data" => [facility_payload("id" => 9005)] } do
          assert_equal 1, FacilitiesPopulator.import_all!
        end

        assert_nil ProductionFacility.find_by(api_id: 123)
        assert ProductionFacility.exists?(api_id: 9005)
      end

      test "destructive import does not enqueue market row broadcasts" do
        assert_no_enqueued_jobs only: Turbo::Streams::ActionBroadcastJob do
          assert_equal 1, FacilitiesPopulator.import_raw_json!(JSON.generate([facility_payload]))
        end
      end

      private

      def facility_payload(overrides = {})
        {
          "id" => 9001,
          "id_commodity" => @commodity.api_id,
          "id_terminal" => @terminal.api_id,
          "price_buy" => "12.34",
          "price_buy_avg" => "10.11",
          "price_sell" => "23.45",
          "price_sell_avg" => "20.22",
          "scu_buy" => 15,
          "scu_buy_avg" => 12,
          "scu_sell_stock" => 75,
          "scu_sell_stock_avg" => 70,
          "scu_sell" => 55,
          "scu_sell_avg" => 50,
          "status_buy" => 1,
          "status_sell" => 1,
          "container_sizes" => [1, 2, 4],
          "date_added" => 1_700_000_000,
          "date_modified" => 1_700_000_001,
          "commodity_name" => @commodity.name,
          "terminal_name" => @terminal.name
        }.merge(overrides)
      end
    end
  end
end
