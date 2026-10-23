class LocationsController < ApplicationController
  def index
    system = params[:star].presence || 'Stanton'
    version = OrbitalState.catalog.version
    if params[:version].present? && params[:version] != version
      return render json: {error: 'Orbital catalog changed; reload the snapshot', catalog_version: version}, status: :conflict
    end
    tick = params[:tick].present? ? Integer(params[:tick], 10) : OrbitalState.current_tick!
    state = OrbitalState.snapshot(tick: tick, systems: [system])
    response.set_header('X-Orbital-Catalog-Version', version)
    render json: Location.where(star_system_name: system).order(:id).map { |location|
      effective = OrbitalState.effective_attributes(location)
      { id: location.id, attributes: effective.merge(name: location.name, classification: location.classification,
          system: system, starmass: OrbitalState.catalog.resolve_alias(system)&.fetch('mass_kg', nil))
          .merge(state.report(location.id)) }
    }
  rescue Orbital::Unavailable, ArgumentError => error
    render json: {error: error.message}, status: :unprocessable_entity
  end

  def show
    user_ship = current_user.user_ships.find(params[:id])
    travel = user_ship.active_travel
    render json: travel ? {in_transit: true, from_location: travel.from_location.name,
      to_location: travel.to_location.name, departure_tick: travel.departure_tick,
      arrival_tick: travel.arrival_tick, current_tick: Tick.current} :
      {in_transit: false, location: user_ship.location&.name}
  end
end
