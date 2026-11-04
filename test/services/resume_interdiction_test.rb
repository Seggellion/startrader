require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class ResumeInterdictionTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @user.update!(user_type: 'admin')
    @travel = gate_start('resume-test')
    @travel.interdict!(100)
  end
  def resolve(token: ResumeInterdiction.review(@travel.reload).token, reason: 'Player requested release')
    ResumeInterdiction.call(id: @travel.id, review_token: token, actor: @user, reason: reason)
  end
  test 'resume retains remainder destination identity cargo player wallet and broker and writes durable audit' do
    before = assets
    identity = @travel.attributes.slice('travel_guid','from_location_id','to_location_id','rabbitmq_environment')
    Tick.instance.update_columns(current_tick: 900)
    result = resolve
    assert_not result.replayed
    assert_equal before, assets
    assert_equal identity, @travel.reload.attributes.slice(*identity.keys)
    assert_not @travel.is_paused?
    assert_equal 908, @travel.arrival_tick
    assert_equal 8, @travel.total_duration_ticks
    assert_equal 'in_transit', @hull.reload.status
    assert_equal 1, TravelResumeAction.count
    assert_equal 'admin', result.action.actor_kind
    assert_equal @user, result.action.admin_user
    assert_equal 0, result.action.before_state['arrival_tick']
    assert_equal 908, result.action.after_state['arrival_tick']
    assert_empty TravelArrivalEvent.all
  end
  test 'duplicate reviewed submission is idempotent even after arrival deletes journey' do
    token = ResumeInterdiction.review(@travel).token
    first = resolve(token: token)
    before = @travel.reload.attributes
    again = resolve(token: token)
    assert again.replayed
    assert_equal first.action.id, again.action.id
    assert_equal before, @travel.reload.attributes
    ShipTravelArrivalProcessor.new(travel:@travel,current_tick:@travel.arrival_tick).call
    final = resolve(token:token)
    assert final.replayed
    assert_equal 1, TravelResumeAction.count
    assert_equal 1, TravelArrivalEvent.count
  end
  test 'saved zero remainder resumes with one tick' do
    @travel.update!(remaining_ticks_from_arrival:0)
    resolve
    assert_equal 101, @travel.reload.arrival_tick
    assert_equal 1, @travel.total_duration_ticks
  end
  test 'changed player location and ship location refuse review without mutation' do
    @player.reload.update_current_location!(@origin)
    before = [@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    review=ResumeInterdiction.review(@travel)
    refute review.allowed
    assert_includes review.reason,'Player location differs'
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert_empty TravelResumeAction.all
    @player.reload.update_current_location!(@gate)
    @hull.update!(location_name:@origin.name)
    refute ResumeInterdiction.review(@travel.reload).allowed
  end
  test 'stale review refuses changed pause without resuming new state' do
    token=ResumeInterdiction.review(@travel).token
    @travel.update!(remaining_ticks_from_arrival:7)
    error=assert_raises(TravelLifecycle::Error){resolve(token:token)}
    assert_equal 'stale_review',error.code
    assert @travel.reload.is_paused?
    assert_equal 7,@travel.remaining_ticks_from_arrival
    assert_empty TravelResumeAction.all
  end
  test 'old replay cannot release a later interdiction cycle' do
    token=ResumeInterdiction.review(@travel).token
    resolve(token:token)
    @travel.interdict!(100)
    before=@travel.reload.attributes
    result=resolve(token:token)
    assert result.replayed
    assert_equal before,@travel.reload.attributes
    resolve
    assert_equal 2,TravelResumeAction.count
  end
  test 'invalid expired and wrong journey reviews cannot cause mutation' do
    assert_raises(TravelLifecycle::Error){resolve(token:'tampered')}
    token=ResumeInterdiction.review(@travel).token
    travel_to 31.minutes.from_now do
      assert_raises(TravelLifecycle::Error){resolve(token:token)}
    end
    assert_raises(TravelLifecycle::Error) do
      ResumeInterdiction.call(id:0,review_token:token,actor:@user,reason:'Wrong target test')
    end
    assert @travel.reload.is_paused?
    assert_empty TravelResumeAction.all
  end
  test 'audit failure rolls back all resume changes' do
    before=[@travel.reload.attributes,@hull.reload.attributes,assets]
    callback=-> {raise 'synthetic audit failure'}
    TravelResumeAction.set_callback(:create,:before,callback)
    assert_raises(RuntimeError){resolve}
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,assets]
    assert_empty TravelResumeAction.all
  ensure
    TravelResumeAction.skip_callback(:create,:before,callback)
  end
  test 'unauthorized actor missing reason and unknown operator reference refuse' do
    token=ResumeInterdiction.review(@travel).token
    @user.update!(user_type:'player')
    assert_raises(TravelLifecycle::Error){resolve(token:token)}
    assert_raises(TravelLifecycle::Error) do
      ResumeInterdiction.call(id:@travel.id,review_token:token,actor: :operator,reason:'Owner request')
    end
    @user.update!(user_type:'admin')
    assert_raises(TravelLifecycle::Error){resolve(token:token,reason:'')}
    assert @travel.reload.is_paused?
    assert_empty TravelResumeAction.all
  end
  test 'operator audit labels actual operator instead of impersonating an administrator' do
    result=ResumeInterdiction.call(id:@travel.id,review_token:ResumeInterdiction.review(@travel).token,
      actor: :operator,operator_reference:'Owner request in Codex',reason:'Release named player journey')
    assert_equal 'operator',result.action.actor_kind
    assert_nil result.action.admin_user_id
    assert_equal 'Owner request in Codex',result.action.actor_label
  end
  test 'final request replay retains actual resumed schedule after cleanup' do
    Tick.instance.update_columns(current_tick:900)
    resolve
    ShipTravelArrivalProcessor.new(travel:@travel,current_tick:908).call
    replay=GateTravelService.new(ship_guid:@hull.guid,gateway_name:'Repair B Gateway',travel_guid:'resume-test').call.travel
    assert replay.request_replayed
    assert_equal 'completed',replay.request_outcome
    assert_equal 900,replay.departure_tick
    assert_equal 908,replay.arrival_tick
  end
end
