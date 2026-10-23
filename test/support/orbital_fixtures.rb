module OrbitalFixtures
  def seed_orbital_catalog
    OrbitalState.catalog.entries.each do |entry|
      Location.find_or_initialize_by(name: entry['name']).update!(api_id: entry['api_id'],
        classification: entry['classification'], star_system_name: entry['system'],
        id_star_system: OrbitalState.catalog.resolve_alias(entry['system'])['api_id'],
        parent_name: entry['parent'], periapsis: 999, apoapsis: 999, mass: 1)
    end
  end
end
