require "test_helper"

class TickChannelTest < ActionCable::Channel::TestCase
  test 'reconnect transmits the same anchored orbital time as a snapshot' do
    tick=OrbitalState.catalog.data.fetch('clock').fetch('orbital_progression').first.fetch('activation_tick')+5
    MarketPriceUpdater.stub(:update_prices!,nil) { Tick.create!(current_tick:tick,sequence:1) }
    TickControl.instance.update!(running:false)
    subscribe
    assert subscription.confirmed?
    assert_has_stream 'tick'
    message=transmissions.last
    assert_equal false,message['running']
    assert_equal tick,message['tick']
    OrbitalState.clock_metadata(tick).each { |key,value| assert_equal value.as_json,message[key.to_s] }
    assert_equal Tick.seconds_per_tick,message['seconds_per_tick']
  end
end
