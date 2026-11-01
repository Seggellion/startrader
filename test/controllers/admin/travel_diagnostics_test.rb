require 'test_helper'
require_relative '../../support/travel_repair_fixtures'
class Admin::TravelDiagnosticsTest < ActionDispatch::IntegrationTest
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @user.update!(provider:'twitch',user_type:'admin')
    @old_omniauth=OmniAuth.config.test_mode
    OmniAuth.config.test_mode=true
    OmniAuth.config.mock_auth[:twitch]=OmniAuth::AuthHash.new(provider:'twitch',uid:@user.uid,info:{name:@user.username})
    get '/auth/twitch/callback'
    assert_redirected_to admin_root_path
  end
  teardown do
    OmniAuth.config.test_mode=@old_omniauth
    OmniAuth.config.mock_auth[:twitch]=nil
  end

  test 'scheduled paused mismatch overdue and no journey render without mutation' do
    get '/admin/ship_travels'
    capture('no-journey')
    assert_response :success
    assert_select 'p',text:'No matching journeys on this page.'
    travel=gate_start
    get '/admin/ship_travels'
    assert_response :success
    assert_includes response.body,'Scheduled travel'
    capture('scheduled')
    travel.interdict!(100)
    get "/admin/ship_travels/#{travel.id}"
    capture("interdicted")
    @player.reload.update_current_location!(@origin)
    before=[travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    get "/admin/ship_travels/#{travel.id}"
    assert_response :success
    assert_includes response.body,'Interdicted'
    assert_includes response.body,'No scheduled arrival while interdicted'
    assert_includes response.body,'Player location differs from ship location'
    assert_includes response.body,'after resume'
    capture('interdicted-mismatch')
    get "/admin/users/#{@user.id}"
    assert_response :success
    assert_includes response.body,'Interdicted'
    get '/admin/users'
    assert_response :success
    assert_includes response.body,'Interdicted'
    assert_equal before,[travel.reload.attributes,@hull.reload.attributes,@player.reload.attributes]
    travel.resume!(100)
    travel.update!(arrival_tick:100)
    get '/admin/ship_travels',params:{state:'awaiting_completion'}
    assert_includes response.body,'Awaiting completion'
    capture('overdue')
    assert ShipTravel.exists?(travel.id)
    assert_select 'form[action^="/admin/ship_travels"]',count:0
    get "/admin/ship_travels/#{travel.id}/edit"
    assert_response :success
    patch "/admin/ship_travels/#{travel.id}",params:{location:{arrival_tick:1}}
    assert_response :method_not_allowed
    assert_equal 100,travel.reload.arrival_tick
  end

  test 'invalid zero is shown as invalid and API includes state without creating travel' do
    travel=gate_start
    ActiveRecord::Base.connection.execute('ALTER TABLE ship_travels DROP CONSTRAINT ship_travels_arrival_state')
    travel.update_columns(arrival_tick:0)
    get '/admin/ship_travels',params:{state:'needs_review'}
    assert_response :success
    assert_includes response.body,'Invalid travel state'
    capture('invalid')
    get "/api/location/#{@hull.id}"
    assert_response :success
    assert_equal 'invalid',JSON.parse(response.body)['travel_state']
    assert_equal 1,ShipTravel.count
  end
  test 'diagnostics retain anonymous and nonadmin access restrictions' do
    delete '/logout'
    get '/admin/ship_travels'
    assert_redirected_to login_path
    @user.update!(user_type:'player')
    get '/auth/twitch/callback'
    get '/admin/ship_travels'
    assert_redirected_to root_path
  end

  test 'eager loaded diagnostics do not add one query per journey' do
    @hull.update!(status:'in_transit')
    saved_trip(arrival_tick:108)
    count_selects=-> {
      statements=[]
      callback=->(*args){sql=args.last[:sql];statements << sql if sql.start_with?('SELECT')}
      ActiveSupport::Notifications.subscribed(callback,'sql.active_record'){get '/admin/ship_travels'}
      assert_response :success
      statements.size
    }
    first=count_selects.call
    12.times do
      ship=@hull.dup;ship.guid=SecureRandom.uuid;ship.save!
      saved_trip(ship,arrival_tick:108)
    end
    assert_operator count_selects.call,:<=,first+2
  end

  def capture(name)
    return unless ENV['TRAVEL_REPAIR_CAPTURE_HTML']=='true'
    dir=Rails.root.join('tmp/jump-travel-browser')
    FileUtils.mkdir_p(dir)
    doc=Nokogiri::HTML(response.body)
    doc.css('script,link').remove
    style=Nokogiri::XML::Node.new('style',doc)
    style.content=File.read(Rails.root.join('app/assets/builds/tailwind.css'))
    doc.at_css('head').add_child(style)
    File.write(dir.join("#{name}.html"),doc.to_html)
  end
end
