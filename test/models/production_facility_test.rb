require "test_helper"

class ProductionFacilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    ProductionFacility.delete_all
    @facility = create_facility
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ProductionFacility.suppress_market_broadcasts = false
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  test "updated at only changes are not market value changes" do
    @facility.touch

    refute @facility.send(:market_values_changed?)
  end

  test "meaningful market value changes broadcast during normal updates" do
    assert_enqueued_jobs 1, only: Turbo::Streams::ActionBroadcastJob do
      @facility.update!(inventory: @facility.inventory + 1)
    end
  end

  test "market broadcasts are suppressed inside without market broadcasts" do
    assert_no_enqueued_jobs only: Turbo::Streams::ActionBroadcastJob do
      ProductionFacility.without_market_broadcasts do
        @facility.update!(inventory: @facility.inventory + 1)
      end
    end
  end

  private

  def create_facility(overrides = {})
    ProductionFacility.create!({
      facility_name: "Lorville CBD",
      production_rate: 5,
      consumption_rate: 1,
      inventory: 10,
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
