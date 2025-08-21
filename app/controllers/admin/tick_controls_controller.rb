# app/controllers/tick_controls_controller.rb
module Admin
class TickControlsController < ApplicationController
  # add your auth here (e.g., before_action :require_admin)

  def start
    TickControl.instance.start!
    TickJob.ensure_scheduled!  # kick off the first job if none queued
      ActionCable.server.broadcast("tick", {
    type: "tick_started",
    seconds_per_tick: Tick::SIMULATED_HOURS_PER_TICK
  })
    redirect_back fallback_location: root_path, notice: "Tick engine started."
  end

  def stop
    TickControl.instance.stop!
    TickJob.cancel_all!        # prevent future runs
      ActionCable.server.broadcast("tick", { type: "tick_stopped" })
    redirect_back fallback_location: root_path, notice: "Tick engine stopped."
  end
end
end