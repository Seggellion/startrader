#!/usr/bin/env ruby
# No Rails boot: no broker warmup, tick creation, jobs, or arrival processing.
require 'json'
require 'optparse'
require 'pg'
require_relative '../lib/orbital/snapshot'

options = { catalog: Orbital::Catalog::DEFAULT_PATH }
OptionParser.new do |p|
  p.banner = 'Usage: bin/codex_exec ruby script/orbital_calibration.rb [options]'
  p.on('--catalog PATH') { |v| options[:catalog] = v }
  p.on('--input PATH', 'Celestial JSON array; - reads stdin instead of connecting to PostgreSQL') { |v| options[:input] = v }
  p.on('--database NAME', 'libpq database name, no connection URL is printed') { |v| options[:database] = v }
  p.on('--tick NUMBER', Float) { |v| options[:tick] = v }
  p.on('--from-id ID') { |v| options[:from] = v }
  p.on('--to-id ID') { |v| options[:to] = v }
  p.on('--speed-gm-per-tick NUMBER', Float) { |v| options[:speed] = v }
end.parse!

begin
  catalog = Orbital::Catalog.new(path: options[:catalog])
  database = nil
  rows = if options[:input]
    JSON.parse(options[:input] == '-' ? STDIN.read : File.read(options[:input]))
  else
    args = options[:database] ? { dbname: options[:database] } : (ENV['DATABASE_URL'] || {})
    connection = PG.connect(args)
    begin
      connection.exec('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
      database = connection.exec('SELECT current_database() AS database, current_user AS role').first
      connection.exec(<<~SQL).to_a
        SELECT id,name,classification,api_id,id_star_system,parent_name,
          star_system_name,periapsis,apoapsis,mass
        FROM locations WHERE star_system_name IN ('Stanton','Pyro','Nyx')
        ORDER BY id
      SQL
    ensure
      connection.exec('ROLLBACK') if connection && connection.transaction_status != PG::PQTRANS_IDLE
      connection.close if connection
    end
  end
  catalog.validate_rows!(rows)
  report = { catalog_version: catalog.version, status: catalog.data['status'],
    database: database, target_count: catalog.entries.count { |e| e.key?('target_distance_gm') },
    identities_valid: true,
    effective: catalog.entries.map do |e|
      raw = rows.find { |r| catalog.identity(r) == catalog.identity(e) }
      { location_id: raw.fetch('id'), catalog: e, imported: raw.slice('periapsis','apoapsis','mass','parent_name') }
    end }
  if options.key?(:tick)
    snapshot = Orbital::Snapshot.new(rows: rows, tick: options[:tick], catalog: catalog)
    report[:snapshot] = snapshot.metadata
    report[:positions] = rows.map { |r| snapshot.report(r.fetch('id')) }
    if options[:from] && options[:to]
      distance = snapshot.distance(options[:from], options[:to])
      report[:route] = { from_id: options[:from], to_id: options[:to], distance_gm: distance }
      if options[:speed]
        speed = Orbital::Geometry.number(options[:speed], 'speed Gm/tick')
        raise Orbital::Unavailable, 'Speed must be positive' unless speed.positive?
        report[:route][:duration_ticks] = [(distance / speed).ceil, 2].max
      end
    end
  end
  puts JSON.pretty_generate(report)
rescue Orbital::Unavailable, PG::Error => e
  # Do not render database error messages that might include connection details.
  error = e.is_a?(Orbital::Unavailable) ? e.message : 'PostgreSQL read-only audit failed'
  warn JSON.generate(error: error)
  exit 1
end
