module Api
  class DistanceCalculatorController < ApplicationController
    skip_before_action :verify_authenticity_token
    def calculate
      input = params.require(:distance).permit(:from, :to, :from_id, :to_id, :system)
      from = OrbitalState.resolve(input[:from], id: input[:from_id], system: input[:system])
      to = OrbitalState.resolve(input[:to], id: input[:to_id], system: input[:system])
      return render json: {error: 'Invalid locations provided.'}, status: :not_found unless from && to
      tick = OrbitalState.current_tick!
      state = OrbitalState.snapshot(tick: tick, systems: [from.star_system_name, to.star_system_name])
      distance = state.distance(from.id, to.id)
      render json: state.metadata.merge(from: from.name, to: to.name, from_id: from.id, to_id: to.id,
        coordinate_frame: "star-centered:#{from.star_system_name}",
        from_point_reference: state.report(from.id)[:point_reference], to_point_reference: state.report(to.id)[:point_reference],
        system: from.star_system_name, from_position_gm: state.position(from.id),
        to_position_gm: state.position(to.id), distance: distance)
    rescue Orbital::Unavailable => error
      render json: {error: error.message}, status: :unprocessable_entity
    end
  end
end
