require "test_helper"

class TickRunnerTest < ActiveSupport::TestCase
  setup do
    TickControl.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM ticks")

    MarketPriceUpdater.stub(:update_prices!, nil) do
      Tick.create!(current_tick: 10, sequence: 1)
    end
  end

  test "lock unavailable skips without incrementing" do
    TickControl.instance.update!(running: true)

    TickRunner.stub(:with_tick_lock, false) do
      assert_equal :locked, TickRunner.run_once!
    end

    assert_equal 10, Tick.current
  end
end
