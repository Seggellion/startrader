require 'test_helper'
require_relative '../support/travel_repair_fixtures'
class ResumeInterdictionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests=false
  include TravelRepairFixtures
  setup do
    setup_travel_repair
    @user.update!(user_type:'admin')
    @travel=gate_start
    @travel.interdict!(100)
  end
  teardown {cleanup_travel_repair}
  test 'two independent admin submissions resume once and retain one audit record' do
    review=ResumeInterdiction.review(@travel)
    ready=Queue.new
    start=Queue.new
    threads=2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout='4s'")
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          ResumeInterdiction.call(id:@travel.id,review_token:review.token,actor:@user,reason:'Concurrent operator request')
        ensure
          connection.execute('RESET lock_timeout')
        end
      end
    end
    pids=threads.map{ready.pop}
    assert_equal 2,pids.uniq.size
    2.times{start<<true}
    results=threads.map do |thread|
      assert thread.join(10),'Resume race timed out'
      thread.value
    end
    assert_equal 1,results.count(&:replayed)
    assert_equal 1,TravelResumeAction.count
    assert_equal 108,@travel.reload.arrival_tick
    assert_not @travel.is_paused?
    assert_equal 'in_transit',@hull.reload.status
    assert_empty TravelArrivalEvent.all
  ensure
    threads&.each{|thread|thread.kill if thread.alive?}
  end
end
