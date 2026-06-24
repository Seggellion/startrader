# app/controllers/tick_controls_controller.rb
module Admin
class TickControlsController < ApplicationController
  # add your auth here (e.g., before_action :require_admin)

  def start
    TickControl.instance.start!
    ActionCable.server.broadcast("tick", {
      type: "tick_started",
      seconds_per_tick: Tick.seconds_per_tick
    })
    redirect_back fallback_location: root_path, notice: "Tick engine started."
  end

  def stop
    TickControl.instance.stop!
    ActionCable.server.broadcast("tick", { type: "tick_stopped" })
    redirect_back fallback_location: root_path, notice: "Tick engine stopped."
  end
end
end
