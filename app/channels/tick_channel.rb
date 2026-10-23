class TickChannel < ApplicationCable::Channel
  def subscribed
    stream_from "tick"
    # Immediately send current status so clients know whether to render
    running = TickControl.order(:id).pick(:running) || false
    tick = Tick.order(:id).pick(:current_tick)
    transmit({
      type: "status",
      running: running,
      tick: tick,
      seconds_per_tick: Tick.seconds_per_tick
    }.merge(tick.nil? ? {} : OrbitalState.clock_metadata(tick)))
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
