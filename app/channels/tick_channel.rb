class TickChannel < ApplicationCable::Channel
  def subscribed
    stream_from "tick"
    # Immediately send current status so clients know whether to render
    running = TickControl.instance.running?
    ActionCable.server.broadcast("tick", {
      type: "status",
      running: running,
      tick: Tick.current,
      seconds_per_tick: Tick.seconds_per_tick
    })
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
