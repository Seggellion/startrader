require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class TravelRepairTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup { setup_travel_repair }

  test 'tick broker failure keeps durable completion and pending event while another journey completes' do
    first=saved_trip
    @hull.update!(status:'in_transit')
    other=@hull.dup;other.guid=SecureRandom.uuid;other.save!
    second=saved_trip(other)
    before=assets
    RabbitmqSender.stub(:send_arrival_event,->(event){raise IOError,'synthetic outage' if event.travel_guid==first.travel_guid}) do
      MarketPriceUpdater.stub(:update_prices!,nil){Tick.increment!}
    end
    refute ShipTravel.exists?(first.id)
    assert TravelArrivalEvent.pending.exists?(travel_guid:first.travel_guid)
    refute ShipTravel.exists?(second.id)
    assert_equal @destination.name,@hull.reload.location_name
    assert_equal 2,TravelRequestReceipt.where(outcome:'completed').count
    assert_equal before,assets
    TravelArrivalEvent.pending.update_all(next_attempt_at:nil)
    RabbitmqSender.stub(:send_arrival_event,nil){ShipArrivalJob.perform_now}
    assert_empty TravelArrivalEvent.pending
    refute ShipTravel.exists?(first.id)
    assert_equal @destination.name,@hull.reload.location_name
  end
end
