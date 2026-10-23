require_relative '../../lib/orbital/snapshot'

class OrbitalState
  def self.catalog
    @catalog ||= Orbital::Catalog.new
  end

  def self.current_tick!
    Tick.order(:id).pick(:current_tick) || raise(Orbital::Unavailable, 'Simulation tick is unavailable')
  end

  def self.snapshot(tick:, systems: nil)
    scope = systems ? Location.where(star_system_name: systems) : Location.all
    Orbital::Snapshot.new(rows: scope.map(&:attributes), tick: tick, catalog: catalog)
  end

  def self.effective_attributes(location)
    entry = catalog.entry_for(location.attributes)
    { parent: entry ? entry['parent'] : location.parent_name,
      periapsis: entry && entry['periapsis_gm'], apoapsis: entry && entry['apoapsis_gm'],
      mass: entry && entry['mass_kg'], orbital_source: entry ? 'calibrated_simulation' : 'unmeasured',
      orbital_model: entry && (entry['coorbital'] ? 'coorbital' : entry['local_offset_gm'] ? 'host_center' : entry['parent'] ? 'kepler' : 'system_origin'),
      local_orbit_radius_gm: entry && entry['local_orbit_radius_gm'], coorbital: entry && entry['coorbital'],
      catalog_version: catalog.version }
  end

  def self.resolve(value, id: nil, system: nil)
    if id.present?
      return Location.find_by(id: id, **(system.present? ? {star_system_name: system} : {}))
    end
    entry = catalog.resolve_alias(value, system: system.presence)
    if entry
      scope = Location.where(api_id: entry['api_id'], classification: entry['classification'], star_system_name: entry['system'])
      raise Orbital::Unavailable, 'Ambiguous or missing calibrated identity' unless scope.count == 1
      location = scope.first
      catalog.entry_for(location.attributes)
      return location
    end
    scope = Location.where('LOWER(name) = ?', value.to_s.strip.downcase)
    scope = scope.where(star_system_name: system) if system.present?
    raise Orbital::Unavailable, 'Ambiguous location name; provide system or ID' if scope.count > 1
    scope.first
  end
end
