require 'test_helper'
require_relative '../../support/travel_repair_fixtures'
class Admin::TravelResumeTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @user.update!(provider:'twitch',user_type:'admin')
    @old_omniauth=OmniAuth.config.test_mode
    OmniAuth.config.test_mode=true
    OmniAuth.config.mock_auth[:twitch]=OmniAuth::AuthHash.new(provider:'twitch',uid:@user.uid,info:{name:@user.username})
    get '/auth/twitch/callback'
    @travel=gate_start
    @travel.interdict!(100)
  end
  teardown do
    OmniAuth.config.test_mode=@old_omniauth
    OmniAuth.config.mock_auth[:twitch]=nil
  end
  def route
    "/admin/ship_travels/#{@travel.id}/resume"
  end
  def token
    get "/admin/ship_travels/#{@travel.id}"
    assert_response :success
    Nokogiri::HTML(response.body).at_css('input[name="review_token"]')&.[]('value')
  end
  test 'admin can review explicitly resume and see durable history' do
    value=token
    assert_select 'input[type=submit][value="Resume saved journey"]',count:1
    assert_includes response.body,'8 remaining ticks'
    before=assets
    post route,params:{review_token:value,reason:'Requested by player'}
    assert_response :see_other
    assert_equal before,assets
    assert_not @travel.reload.is_paused?
    assert_equal 1,TravelResumeAction.count
    follow_redirect!
    assert_includes response.body,'Recent resumes'
    assert_includes response.body,'Requested by player'
  end
  test 'mismatched player has explanation and no resume form' do
    @player.reload.update_current_location!(@origin)
    before=[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert_nil token
    assert_includes response.body,'Resume unavailable'
    assert_includes response.body,'Player location differs'
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    capture('blocked')
  end
  test 'stale review returns actionable error and never resumes' do
    value=token
    @travel.update!(remaining_ticks_from_arrival:7)
    post route,params:{review_token:value,reason:'Requested by player'}
    assert_response :unprocessable_entity
    assert_includes response.body,'The journey changed since review.'
    assert @travel.reload.is_paused?
    assert_empty TravelResumeAction.all
  end
  test 'anonymous and player cannot use the admin resume action' do
    value=token
    delete '/logout'
    post route,params:{review_token:value,reason:'Unauthorized'}
    assert_redirected_to login_path
    @user.update!(user_type:'player')
    get '/auth/twitch/callback'
    post route,params:{review_token:value,reason:'Unauthorized'}
    assert_redirected_to root_path
    assert @travel.reload.is_paused?
    assert_empty TravelResumeAction.all
  end
  test 'CSRF protection rejects a signed review without a session authenticity token' do
    value=token
    previous=Admin::ShipTravelsController.allow_forgery_protection
    Admin::ShipTravelsController.allow_forgery_protection=true
    post route,params:{review_token:value,reason:'Missing CSRF'}
    assert_response :unprocessable_entity
    assert @travel.reload.is_paused?
    assert_empty TravelResumeAction.all
    value=token
    csrf=Nokogiri::HTML(response.body).at_css("form[action='#{route}'] input[name='authenticity_token']")['value']
    post route,params:{review_token:value,reason:'Valid session CSRF',authenticity_token:csrf}
    assert_response :see_other
    assert_not @travel.reload.is_paused?
  ensure
    Admin::ShipTravelsController.allow_forgery_protection=previous
  end
  test 'ready detail page is captured for Chrome and views leave state unchanged' do
    before=[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    assert token
    capture('ready')
    assert_equal before,[@travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
  end
  def capture(name)
    return unless ENV['TRAVEL_RESUME_CAPTURE']=='true'
    dir=Rails.root.join('tmp/travel-resume-browser')
    FileUtils.mkdir_p(dir)
    doc=Nokogiri::HTML(response.body)
    doc.css('script,link').remove
    style=Nokogiri::XML::Node.new('style',doc)
    style.content=File.read(Rails.root.join('app/assets/builds/tailwind.css'))
    doc.at_css('head').add_child(style)
    # Review tokens and session CSRF fields are irrelevant to static visual QA.
    doc.css('input[name=review_token],input[name=authenticity_token]').each{|input|input['value']='synthetic-visual-token'}
    File.write(dir.join("#{name}.html"),doc.to_html)
  end
end
