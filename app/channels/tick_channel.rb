class TickChannel < ApplicationCable::Channel
  def subscribed
    stream_from "tick"
    # Immediately send current status so clients know whether to render
    running = TickControl.order(:id).pick(:running) || false
    transmit({
      type: "status",
      running: running,
      tick: Tick.order(:id).pick(:current_tick),
      catalog_version: OrbitalState.catalog.version,
      simulated_seconds_per_tick: OrbitalState.catalog.data.fetch('clock').fetch('simulated_seconds_per_tick'),
      seconds_per_tick: Tick.seconds_per_tick
    })
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
