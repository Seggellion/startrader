require 'yaml'
require 'digest'
require 'time'
require_relative 'geometry'
require_relative 'clock'

module Orbital
  # Effective authority is the immutable catalog, not importer-owned numbers.
  class Catalog
    DEFAULT_PATH = File.expand_path('../../config/orbital_calibrations/v3.yml', __dir__)
    attr_reader :data, :version

    def initialize(path: DEFAULT_PATH, data: nil)
      raw = data || YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      @data = freeze_tree(Marshal.load(Marshal.dump(raw)))
      @version = "#{@data.fetch('version')}:#{Digest::SHA256.hexdigest(Marshal.dump(@data))[0,16]}"
      keys = entries.map { |e| identity(e) }
      raise Unavailable, 'Duplicate catalog identity' unless keys.uniq.length == keys.length
    end

    def entries = data.fetch('bodies')

    def entry_for(row)
      entry = entries.find { |e| identity(e) == identity(row) }
      return nil unless entry
      raise Unavailable, 'Canonical identity/name mismatch' unless entry.fetch('name') == row['name']
      allowed = entry.fetch('accepted_raw_parents', [entry['parent']])
      raw_parent = row['parent_name'].to_s.strip
      raise Unavailable, "Parent mismatch for #{row['name']}" unless allowed.map(&:to_s).include?(raw_parent)
      entry
    end

    def validate_rows!(rows, complete: true)
      groups = rows.group_by { |r| identity(r) }
      entries.each do |e|
        matches = groups.fetch(identity(e), [])
        next if !complete && matches.empty?
        raise Unavailable, "Expected one #{e['name']}; found #{matches.length}" unless matches.length == 1
        entry_for(matches.first)
      end
      true
    end

    def ready!
      raise Unavailable, 'Orbital simulation parameters await an explicit product decision' unless data['status'] == 'approved'
      expected_units = { 'distance' => 'Gm', 'mass' => 'kg', 'time' => 'seconds', 'phase' => 'degrees' }
      raise Unavailable, 'Explicit Gm/kg/seconds/degree units are required' unless data['units'] == expected_units
      clock = data.fetch('clock')
      Time.iso8601(clock.fetch('epoch'))
      %w[origin_tick origin_simulation_seconds simulated_seconds_per_tick].each do |key|
        Geometry.number(clock[key], key)
      end
      raise Unavailable, 'Simulation clock step must be positive' unless Geometry.number(clock['simulated_seconds_per_tick'], 'clock step').positive?
      Clock.new(clock)
      entries.each do |entry|
        Geometry.period_seconds(1, entry['mass_kg']) if entry.key?('mass_kg')
        if %w[star star_system].include?(entry['classification'])
          Geometry.period_seconds(1, entry['mass_kg'])
        elsif entry['coorbital']
          model = entry.fetch('coorbital')
          factor = Geometry.number(model['radial_factor'], 'coorbital radial factor')
          raise Unavailable, 'Coorbital radial factor must be positive' unless factor.positive?
          Geometry.number(model['phase_offset_deg'], 'coorbital angle')
        elsif entry['local_offset_gm']
          %w[x y z].each { |axis| Geometry.number(entry['local_offset_gm'][axis], "offset #{axis}") }
        else
          if data['target_semantics'] == 'constant_circular_radius' && entry['target_distance_gm']
            target = Geometry.number(entry['target_distance_gm'], 'target Gm')
            unless entry['periapsis_gm'] == target && entry['apoapsis_gm'] == target
              raise Unavailable, 'Circular orbital bounds must equal the supplied target'
            end
          end
          Geometry.position(periapsis_gm: entry['periapsis_gm'], apoapsis_gm: entry['apoapsis_gm'],
            mass_kg: 1, phase_deg: entry['phase_deg'], elapsed_seconds: 0)
        end
      end
      true
    rescue KeyError, ArgumentError, TypeError
      raise Unavailable, 'Catalog simulation parameters are incomplete or invalid'
    end

    def resolve_alias(value, system: nil)
      normalize = ->(s) { s.to_s.downcase.gsub(/[^a-z0-9]/, '') }
      matches = entries.select do |e|
        (!system || e['system'] == system) &&
          ([e['name']] + e.fetch('aliases', [])).any? { |a| normalize.call(a) == normalize.call(value) }
      end
      raise Unavailable, 'Ambiguous orbital alias' if matches.length > 1
      matches.first
    end

    def identity(row)
      [row['system'] || row['star_system_name'], row['classification'], Integer(row['api_id'] || 0)]
    rescue ArgumentError, TypeError
      raise Unavailable, 'Invalid external identity'
    end

    private

    def freeze_tree(value)
      case value
      when Hash then value.each { |k, v| freeze_tree(k); freeze_tree(v) }
      when Array then value.each { |v| freeze_tree(v) }
      end
      value.freeze
    end
  end
end
