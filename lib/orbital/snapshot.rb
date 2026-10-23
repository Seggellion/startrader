require_relative 'catalog'

module Orbital
  class Snapshot
    attr_reader :catalog, :tick, :elapsed_seconds

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
      step = Geometry.number(@clock['simulated_seconds_per_tick'], 'simulated seconds per tick')
      raise Unavailable, 'Simulation clock step must be positive' unless step.positive?
      @elapsed_seconds = Geometry.number(@clock['origin_simulation_seconds'], 'anchor seconds') +
        (@tick - Geometry.number(@clock['origin_tick'], 'anchor tick')) * step
    end

    def metadata
      { catalog_version: catalog.version, distance_unit: 'Gm', mass_unit: 'kg',
        current_tick: tick, simulation_seconds: elapsed_seconds, clock: @clock }
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
      local = if entry.key?('local_offset_gm')
        entry.fetch('local_offset_gm').transform_keys(&:to_sym)
      else
        parent_entry = catalog.entry_for(parent)
        raise Unavailable, 'Central mass is unavailable' unless parent_entry
        Geometry.position(periapsis_gm: entry['periapsis_gm'], apoapsis_gm: entry['apoapsis_gm'],
          phase_deg: entry['phase_deg'], mass_kg: parent_entry['mass_kg'], elapsed_seconds: elapsed_seconds)
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
      reference = %w[city outpost].include?(row['classification']) ? 'host_center_approximation' : 'body_center'
      metadata.merge(location_id: id, coordinate_frame: "star-centered:#{row['star_system_name']}",
        point_reference: reference, position_gm: position(id), available: true)
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
