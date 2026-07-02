require "test_helper"

class MarketPriceUpdaterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    ProductionFacility.delete_all
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ProductionFacility.suppress_market_broadcasts = false
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  test "updates prices without broadcasting each changed market row by default" do
    facilities = 3.times.map do |index|
      create_facility(facility_name: "Market Facility #{index}", inventory: 0)
    end

    assert_no_enqueued_jobs only: Turbo::Streams::ActionBroadcastJob do
      MarketPriceUpdater.update_prices!
    end

    assert facilities.any? { |facility| facility.reload.local_sell_price > 100 }
  end

  private

  def create_facility(overrides = {})
    ProductionFacility.create!({
      facility_name: "Market Facility",
      production_rate: 0,
      consumption_rate: 0,
      inventory: 0,
      max_inventory: 100,
      local_buy_price: 80,
      local_sell_price: 100,
      price_buy: 80,
      price_sell: 100,
      scu_buy: 10,
      scu_sell: 10,
      scu_sell_stock: 50,
      status_buy: 1,
      status_sell: 1,
      commodity_name: "Agricium",
      terminal_name: "Lorville CBD",
      location_name: "Lorville"
    }.merge(overrides))
  end
end
