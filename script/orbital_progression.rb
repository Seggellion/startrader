#!/usr/bin/env ruby
# Pure release preparation. Never edits an old catalog, a database, or a tick.
require 'optparse'
require_relative '../lib/orbital/catalog'

options = {}
OptionParser.new do |p|
  p.banner = 'Usage: ruby script/orbital_progression.rb --source PATH --output PATH --version NAME --current-tick N --activation-tick N --multiplier RATE'
  %w[source output version].each { |key| p.on("--#{key} VALUE") { |v| options[key] = v } }
  %w[current-tick activation-tick].each { |key| p.on("--#{key} N", Integer) { |v| options[key] = v } }
  p.on('--multiplier RATE', Float) { |v| options['multiplier'] = v }
end.parse!

begin
  %w[source output version current-tick activation-tick multiplier].each { |key| options.fetch(key) }
  source = Orbital::Catalog.new(path: options.fetch('source'))
  source.ready!
  raise Orbital::Unavailable, 'Use a new catalog version' if options['version'] == source.data['version']
  raise Orbital::Unavailable, 'Activation must be in the future' unless options['activation-tick'] > options['current-tick']
  data = Marshal.load(Marshal.dump(source.data))
  data['version'] = options.fetch('version')
  (data.fetch('clock')['orbital_progression'] ||= []) << {
    'activation_tick' => options.fetch('activation-tick'),
    'orbital_progression_multiplier' => options.fetch('multiplier') }
  candidate = Orbital::Catalog.new(data: data)
  candidate.ready!
  File.open(options.fetch('output'), File::WRONLY | File::CREAT | File::EXCL) { |f| f.write(YAML.dump(data)) }
  puts "Prepared #{candidate.version}; activation #{options['activation-tick']}; orbital multiplier #{options['multiplier']}"
rescue KeyError, Orbital::Unavailable, Errno::EEXIST => e
  warn "Orbital progression preparation failed: #{e.message}"
  exit 1
end
