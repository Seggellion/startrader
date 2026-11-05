require_relative '../../test/test_helper'
require_relative '../../test/support/travel_repair_fixtures'
require_relative 'ship_only_resume_5071_operator'
class ResumeSeparatedInterdictionTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @travel=saved_trip(from_location:@origin)
    @travel.interdict!(95)
    @player.update_current_location!(@gate)
    @plan={'travel'=>@travel.attributes,'ship_id'=>@hull.id,'user_id'=>@user.id,'player_id'=>@player.id,
      'player_location'=>@gate.name,'ship_location'=>@origin.name,
      'fingerprint'=>ResumeInterdiction.fingerprint(@travel.reload)}
  end
  def resume
    ResumeSeparatedInterdiction.call(plan:@plan,reference:'synthetic separated resume',reason:'Owner-approved ship-only test.')
  end
  test 'ship-only exception preserves player and assets through resumed arrival and is idempotent' do
    before=assets
    player_before=@player.reload.attributes
    result=resume
    assert_equal 5,result.action.remaining_ticks
    assert_equal 105,result.action.arrival_tick
    assert_equal @gate.name,@player.reload.current_location_name
    assert_equal player_before,@player.attributes
    assert_equal before,assets
    assert_equal @gate.name,result.action.before_state.dig('location_exception','player_location')
    assert resume.replayed
    ShipTravelArrivalProcessor.new(travel:@travel.reload,current_tick:105).call
    assert_equal @destination.name,@hull.reload.location_name
    assert_equal @gate.name,@player.reload.current_location_name
    assert_equal before,assets
    assert resume.replayed
    assert_equal 1,TravelResumeAction.count
  end
  test 'changed pause or player location is refused without edits' do
    @player.update_current_location!(@destination)
    before=[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert_raises(RuntimeError){resume}
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert_empty TravelResumeAction.all
  end
  test 'audit failure rolls back ship and timing while preserving separated player' do
    before=[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes,assets]
    TravelResumeAction.stub(:create!,->(**_){raise 'synthetic audit write failure'}) do
      assert_raises(RuntimeError){resume}
    end
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes,assets]
    assert_empty TravelResumeAction.all
  end
  test 'another blocked condition cannot use the player-separation exception' do
    @hull.reload.update!(status:'docked')
    @plan['fingerprint']=ResumeInterdiction.fingerprint(@travel.reload)
    before=[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    error=assert_raises(RuntimeError){resume}
    assert_equal 'Another eligibility check failed',error.message
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert_empty TravelResumeAction.all
  end
end
