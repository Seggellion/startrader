require_relative '../../test/test_helper'
require_relative '../../test/support/travel_repair_fixtures'
require_relative '../../test/support/fake_rabbitmq'
require_relative 'reviewed_arrival_catchup_operator'
require 'tmpdir'

class ReviewedArrivalCatchupTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @origin.update!(name:'Stanton Gateway (Pyro)')
    @destination.update!(name:'Pyro Gateway (Stanton)')
    @shard.update!(name:'Seggellion')
    @hull.reload.update!(location_name:@origin.name)
    @player.update_current_location!(@origin)
    travel=saved_trip(rabbitmq_environment:'prod')
    ShipTravelArrivalProcessor.new(travel:travel,current_tick:100).call
    @event=TravelArrivalEvent.sole
    first=FakeRabbitmq::ChannelRecorder.new
    RabbitmqConnection.stub(:channel_for,first.to_proc){@event.deliver!}
    @plan={event_id:@event.id,receipt_id:TravelRequestReceipt.sole.id,ship_id:@hull.id,
      user_id:@user.id,shard_id:@shard.id,player_id:@player.id,to_location_id:@destination.id,origin:@origin.name,destination:@destination.name}
    @directory=Dir.mktmpdir('ac3-catchup-test-')
    @journal=File.join(@directory,'attempt.json')
    @broker=FakeRabbitmq::ChannelRecorder.new
  end
  teardown { FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory) }
  def deliver
    fingerprint=ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
    RabbitmqConnection.stub(:channel_for,@broker.to_proc) do
      ReviewedArrivalCatchup.deliver!(fingerprint:fingerprint,journal:@journal,reason:'Explicit synthetic owner authorization',plan:@plan)
    end
  end
  test 'one correlated dev copy preserves all source rows and original message identities' do
    before=ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
    result=deliver
    assert_equal 'broker_confirmed',result[:state]
    assert_equal ['dev'],@broker.requested_environments
    pub=@broker.publications_for('dev').sole
    assert_equal @event.event_guid,pub[:message_id]
    assert_equal @event.travel_guid,pub[:headers][:travel_guid]
    fields=pub[:message].split('|')
    assert_equal 'repair-secret',fields[10]
    assert_equal 'Pyro Gateway (Stanton)',fields[12]
    assert_equal before,ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
    assert_equal 'prod',@event.reload.rabbitmq_environment
    assert_equal 1,TravelArrivalEvent.count
    assert_equal 'broker_confirmed',JSON.parse(File.read(@journal))['state']
    assert_raises(Errno::EEXIST){deliver}
    assert_equal 1,@broker.publications_for('dev').size
  end
  test 'changed reviewed state or an in-progress leg prevents delivery' do
    fingerprint=ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
    @hull.reload.update!(location_name:@origin.name)
    assert_raises(RuntimeError) do
      RabbitmqConnection.stub(:channel_for,@broker.to_proc) do
        ReviewedArrivalCatchup.deliver!(fingerprint:fingerprint,journal:@journal,reason:'Authorized',plan:@plan)
      end
    end
    assert_empty @broker.requested_environments
    refute File.exist?(@journal)
  end
  test 'uncertain publication stays journaled and never retries automatically' do
    before=ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
    RabbitmqSender.stub(:send_arrival_event,->(_){raise IOError,'synthetic uncertain confirm'}) do
      assert_raises(IOError){deliver}
    end
    assert_equal 'uncertain_or_failed',JSON.parse(File.read(@journal))['state']
    assert_raises(Errno::EEXIST){deliver}
    assert_empty @broker.requested_environments
    assert_equal before,ReviewedArrivalCatchup.review(plan:@plan)[:fingerprint]
  end
end
