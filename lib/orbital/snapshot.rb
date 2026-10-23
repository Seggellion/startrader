require_relative 'catalog'

module Orbital
  class Snapshot
    attr_reader :catalog, :tick, :elapsed_seconds, :orbital_seconds

    def initialize(rows:, tick:, catalog: Catalog.new)
      @catalog = catalog
      catalog.ready!
      @tick = Geometry.number(tick, 'snapshot tick')
      @rows = rows.map { |r| r.transform_keys(&:to_s) }
      catalog.validate_rows!(@rows, complete: false)
      @by_id = @rows.group_by { |r| r.fetch('id').to_s }
      @by_name = @rows.group_by { |r| [r['star_system_name'], r['name']] }
      @positions = {}
      @clock = catalog.data.fetch('clock')
      @clock_metadata = Clock.new(@clock).metadata(@tick)
      @elapsed_seconds = @clock_metadata.fetch(:simulation_seconds)
      @orbital_seconds = @clock_metadata.fetch(:orbital_seconds)
    end

    def metadata
      { catalog_version: catalog.version, distance_unit: 'Gm', mass_unit: 'kg',
        current_tick: tick }.merge(@clock_metadata)
    end

    def position(id, visited: [])
      key = id.to_s
      return @positions[key] if @positions.key?(key)
      raise Unavailable, 'Cyclic orbital parent graph' if visited.include?(key)
      rows = @by_id.fetch(key, [])
      raise Unavailable, 'Missing or duplicate location ID' unless rows.length == 1
      row = rows.first
      entry = catalog.entry_for(row)
      # Imported moon/station placeholder elements are not measured local orbits.
      unless entry
        if %w[city outpost].include?(row['classification'])
          parent = parent_row(row, row['parent_name'])
          raise Unavailable, 'Surface destination requires a body host' unless %w[planet moon].include?(parent['classification'])
          return @positions[key] = position(parent['id'], visited: visited + [key])
        end
        raise Unavailable, "Unmeasured orbital position for #{row['name']}"
      end
      if %w[star star_system].include?(entry['classification'])
        Geometry.period_seconds(1, entry['mass_kg']) # validate explicit positive kg
        raise Unavailable, 'Star must be the root of its frame' if entry['parent']
        return @positions[key] = { x: 0.0, y: 0.0, z: 0.0 }.freeze
      end
      parent = parent_row(row, entry.fetch('parent'))
      parent_position = position(parent['id'], visited: visited + [key])
      if entry['coorbital']
        parent_entry = catalog.entry_for(parent)
        raise Unavailable, 'Coorbital station requires a calibrated planet' unless parent_entry && parent['classification'] == 'planet'
        root = parent_row(parent, parent_entry.fetch('parent'))
        raise Unavailable, 'Coorbital reference must orbit its system star' unless %w[star star_system].include?(root['classification'])
        center = position(root['id'], visited: visited + [key])
        model = entry.fetch('coorbital')
        angle = Geometry.number(model.fetch('phase_offset_deg'), 'coorbital angle') * Math::PI / 180
        factor = Geometry.number(model.fetch('radial_factor'), 'coorbital radial factor')
        x = parent_position[:x] - center[:x]; y = parent_position[:y] - center[:y]
        offset = {x: factor * (x*Math.cos(angle)-y*Math.sin(angle)),
          y: factor * (x*Math.sin(angle)+y*Math.cos(angle)), z: parent_position[:z]-center[:z]}
        return @positions[key] = Geometry.add(center, offset).freeze
      end
      local = if entry.key?('local_offset_gm')
        entry.fetch('local_offset_gm').transform_keys(&:to_sym)
      else
        parent_entry = catalog.entry_for(parent)
        raise Unavailable, 'Central mass is unavailable' unless parent_entry
        Geometry.position(periapsis_gm: entry['periapsis_gm'], apoapsis_gm: entry['apoapsis_gm'],
          phase_deg: entry['phase_deg'], mass_kg: parent_entry['mass_kg'], elapsed_seconds: orbital_seconds)
      end
      @positions[key] = Geometry.add(parent_position, local).freeze
    end

    def distance(from_id, to_id)
      from = unique_row(from_id)
      to = unique_row(to_id)
      raise Unavailable, 'Direct distance requires one system frame' unless
        from['star_system_name'] && from['star_system_name'] == to['star_system_name']
      Geometry.distance(position(from_id), position(to_id))
    end

    def report(id)
      row = unique_row(id)
      entry = catalog.entry_for(row)
      parent_name = entry ? entry['parent'] : row['parent_name']
      parent_position = parent_name && position(parent_row(row, parent_name)['id'])
      world = position(id)
      local = parent_position && %i[x y z].to_h { |axis| [axis, world.fetch(axis)-parent_position.fetch(axis)] }
      reference = %w[city outpost].include?(row['classification']) ? 'host_center_approximation' : 'body_center'
      metadata.merge(location_id: id, coordinate_frame: "star-centered:#{row['star_system_name']}",
        point_reference: reference, position_gm: world, parent: parent_name,
        orbital_model: entry && (entry['coorbital'] ? 'coorbital' : entry['local_offset_gm'] ? 'host_center' : parent_name ? 'kepler' : 'system_origin'),
        parent_position_gm: parent_position, local_position_gm: local,
        local_distance_gm: parent_position && Geometry.distance(world,parent_position), available: true)
    rescue Unavailable => e
      metadata.merge(location_id: id, available: false, unavailable_reason: e.message)
    end

    private

    def unique_row(id)
      rows = @by_id.fetch(id.to_s, [])
      raise Unavailable, 'Missing or duplicate location ID' unless rows.length == 1
      rows.first
    end

    def parent_row(row, name)
      matches = @by_name.fetch([row['star_system_name'], name], [])
      raise Unavailable, "Missing or ambiguous parent for #{row['name']}" unless matches.length == 1
      matches.first
    end
  end
end
