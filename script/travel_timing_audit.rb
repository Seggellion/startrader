#!/usr/bin/env ruby
# Read-only calibration audit. No Rails boot, jobs, tick creation or arrivals.
require 'json'
require 'optparse'
require 'pg'
require_relative '../lib/orbital/snapshot'
require_relative '../lib/travel_timing'

options={}
OptionParser.new do |p|
  p.on('--input PATH', 'JSON object with tick, seconds_per_tick and locations') { |v| options[:input]=v }
  p.on('--tick TICK', Integer, 'Use one explicit snapshot tick') { |v| options[:tick]=v }
end.parse!

begin
  input=if options[:input]
    JSON.parse(File.read(options[:input]))
  else
    connection=PG.connect(ENV.fetch('DATABASE_URL'))
    begin
      connection.exec('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
      tick=connection.exec('SELECT current_tick FROM ticks ORDER BY id LIMIT 1').first&.fetch('current_tick')
      seconds=connection.exec("SELECT value FROM settings WHERE key='seconds_per_tick'").first&.fetch('value')
      rows=connection.exec("SELECT id,name,classification,api_id,parent_name,star_system_name FROM locations WHERE star_system_name IN ('Stanton','Pyro','Nyx') ORDER BY id").to_a
      {'tick'=>tick,'seconds_per_tick'=>seconds,'locations'=>rows}
    ensure
      connection.exec('ROLLBACK') unless connection.transaction_status==PG::PQTRANS_IDLE
      connection.close
    end
  end
  seconds=Float(input.fetch('seconds_per_tick'))
  raise ArgumentError,'Expected the authoritative persisted 15-second setting' unless seconds==15
  tick=options.fetch(:tick) { Integer(input.fetch('tick')) }
  catalog=Orbital::Catalog.new
  rows=input.fetch('locations')
  catalog.validate_rows!(rows)
  snapshot=Orbital::Snapshot.new(rows:rows,tick:tick,catalog:catalog)
  routes=[['Pyro','Pyro I','Monox'],['Pyro','Pyro IV','Pyro V'],['Nyx','Nyx I','Nyx II'],
    ['Stanton','Hurston','Crusader'],['Stanton','Hurston','Arial']].map do |system,from,to|
    ids=[from,to].map do |name|
      matches=rows.select { |r| r['star_system_name']==system && r['name']==name }
      raise Orbital::Unavailable,'Route requires one canonical location per endpoint' unless matches.length==1
      matches.first.fetch('id')
    end
    distance=snapshot.distance(*ids)
    TravelTiming.metadata(duration_ticks:TravelTiming.duration_ticks(distance),seconds_per_tick:seconds).merge(
      system:system,from:from,to:to,from_id:ids[0],to_id:ids[1],distance_gm:distance)
  end
  puts JSON.pretty_generate(snapshot.metadata.merge(routes:routes))
rescue PG::Error
  warn JSON.generate(error:'Read-only PostgreSQL audit failed'); exit 1
rescue Orbital::Unavailable,ArgumentError,KeyError => error
  warn JSON.generate(error:error.message); exit 1
end
