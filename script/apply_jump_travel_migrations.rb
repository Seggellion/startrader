# Version-scoped operator process: no Rails application/initializers or model callbacks.
require 'active_record'
require 'active_support/all'
require 'json'
require 'digest'
require 'optparse'
require 'open3'
require_relative '../db/migrate/20261101010000_create_travel_lifecycle_receipts'
require_relative '../db/migrate/20261101010100_guard_travel_arrival_state'
require_relative '../db/migrate/20261101010200_guard_unfinished_ship_journeys'
require_relative '../db/migrate/20261101010300_validate_travel_arrival_state'

options={}
OptionParser.new do |p|
  p.on('--database NAME'){|x|options[:database]=x}
  p.on('--expected-sha SHA'){|x|options[:sha]=x}
  p.on('--phase PHASE'){|x|options[:phase]=x}
  p.on('--apply'){options[:apply]=true}
end.parse!
abort 'Expected database, full candidate SHA and phase expand/guards required' unless
  options[:database].present? && options[:sha].to_s.match?(/\A[0-9a-f]{40}\z/) && %w[expand guards].include?(options[:phase])
root=File.expand_path('..',__dir__)
sha,_,status=Open3.capture3('git','-C',root,'rev-parse','HEAD')
abort 'Candidate revision mismatch' unless status.success? && sha.strip==options[:sha]
paths=%w[script/apply_jump_travel_migrations.rb db/migrate/20261101010000_create_travel_lifecycle_receipts.rb db/migrate/20261101010100_guard_travel_arrival_state.rb db/migrate/20261101010200_guard_unfinished_ship_journeys.rb db/migrate/20261101010300_validate_travel_arrival_state.rb]
_,_,clean=Open3.capture3('git','-C',root,'diff','--quiet','HEAD','--',*paths)
abort 'Operator or migration source differs from committed candidate' unless clean.success?
ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
c=ActiveRecord::Base.connection
c.execute("SET application_name='startrader_jump_travel_operator'")
c.execute("SET lock_timeout='2s'")
c.execute("SET statement_timeout='120s'")
c.execute('SET default_transaction_read_only=on') unless options[:apply]
actual=c.select_value('SELECT current_database()')
abort 'Database mismatch; no migration attempted' unless actual==options[:database]
versions=ActiveRecord::Base.connection_pool.schema_migration
applied=versions.versions
condition=GuardTravelArrivalState::CONDITION
invalid=c.select_value("SELECT count(*) FROM ship_travels WHERE (#{condition}) IS NOT TRUE").to_i
duplicates=c.select_value('SELECT count(*) FROM (SELECT user_ship_id FROM ship_travels WHERE completed_at_tick IS NULL GROUP BY user_ship_id HAVING count(*)>1) d').to_i
abort 'Invalid timing or duplicate unfinished journeys require review; no rows repaired' unless invalid.zero? && duplicates.zero?
ids=c.select_values('SELECT id FROM ship_travels ORDER BY id LIMIT 1001').map(&:to_i)
abort 'Protected snapshot exceeds bounded operator scope' if ids.size>1000
scope=ids.empty? ? 'NULL' : ids.join(',')
fingerprint=-> {
  queries={
    travel:"SELECT * FROM ship_travels WHERE id IN (#{scope}) ORDER BY id",
    ships:"SELECT * FROM user_ships WHERE id IN (SELECT user_ship_id FROM ship_travels WHERE id IN (#{scope})) ORDER BY id",
    players:"SELECT * FROM shard_users WHERE id IN (SELECT shard_user_id FROM user_ships WHERE id IN (SELECT user_ship_id FROM ship_travels WHERE id IN (#{scope}))) ORDER BY id",
    cargo:"SELECT * FROM user_ship_cargos WHERE user_ship_id IN (SELECT user_ship_id FROM ship_travels WHERE id IN (#{scope})) ORDER BY id"
  }
  queries.transform_values{|sql|Digest::SHA256.hexdigest(JSON.generate(c.select_all(sql).to_a))}
}
before=fingerprint.call
entries=options[:phase]=='expand' ?
  [['20261101010000',CreateTravelLifecycleReceipts,true]] :
  [['20261101010100',GuardTravelArrivalState,true],['20261101010200',GuardUnfinishedShipJourneys,false],['20261101010300',ValidateTravelArrivalState,true]]
abort 'Expand tables must exist before guards' if options[:phase]=='guards' &&
  (!c.data_source_exists?('travel_request_receipts') || !c.data_source_exists?('travel_arrival_events'))
report={at_utc:Time.now.utc.iso8601,mode:options[:apply] ? 'apply' : 'dry_run',phase:options[:phase],
  source_sha:sha.strip,protected_travel_ids:ids,invalid:invalid,duplicate_groups:duplicates,versions:[]}
ActiveRecord::Migration.verbose=false
entries.each do |version,klass,transactional|
  action=applied.include?(version) ? 'already_applied' : 'pending'
  if options[:apply] && !applied.include?(version)
    operation=-> {klass.new.migrate(:up);versions.create_version(version)}
    transactional ? ActiveRecord::Base.transaction { operation.call } : operation.call
    action='applied'
  end
  report[:versions] << {version:version,action:action}
end
if options[:apply]
  expected={
    'index_travel_request_receipts_on_travel_guid'=>['travel_request_receipts',['travel_guid'],nil],
    'index_travel_arrival_events_on_event_guid'=>['travel_arrival_events',['event_guid'],nil],
    'index_travel_arrival_events_on_travel_guid'=>['travel_arrival_events',['travel_guid'],nil]
  }
  expected['index_one_unfinished_journey_per_ship']=['ship_travels',['user_ship_id'],'(completed_at_tick IS NULL)'] if options[:phase]=='guards'
  expected.each do |name,(table,columns,predicate)|
    index=c.indexes(table).find{|i|i.name==name}
    valid=c.select_value("SELECT indisvalid AND indisready FROM pg_index WHERE indexrelid=#{c.quote(name)}::regclass")
    abort "Index verification failed: #{name}" unless index && index.unique && index.columns==columns && index.where==predicate && valid
  end
  if options[:phase]=='guards'
    check=c.select_value("SELECT convalidated FROM pg_constraint WHERE conname='ship_travels_arrival_state' AND conrelid='ship_travels'::regclass")
    abort 'Conditional check is not validated' unless check
  end
end
after=fingerprint.call
abort 'Protected travel/ship/player/cargo changed; stop operational rollout' unless before==after
report[:protected_fingerprints_unchanged]=true
report[:protected_fingerprints]=after
puts JSON.pretty_generate(report)
ActiveRecord::Base.connection_pool.disconnect!
