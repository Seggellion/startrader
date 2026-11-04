# One additive audit-table migration only. No Rails boot, models, callbacks or broker.
require 'active_record'
require 'active_support/all'
require 'json'
require 'digest'
require 'optparse'
require 'open3'
require_relative '../db/migrate/20261104010000_create_travel_resume_actions'
options={}
OptionParser.new do |parser|
  parser.on('--database NAME'){|v|options[:database]=v}
  parser.on('--expected-sha SHA'){|v|options[:sha]=v}
  parser.on('--apply'){options[:apply]=true}
end.parse!
abort 'Expected database and full committed candidate SHA required' unless
  options[:database].present? && options[:sha].to_s.match?(/\A[0-9a-f]{40}\z/)
root=File.expand_path('..',__dir__)
sha,_,status=Open3.capture3('git','-C',root,'rev-parse','HEAD')
abort 'Source revision mismatch' unless status.success? && sha.strip==options[:sha]
paths=%w[script/apply_travel_resume_migration.rb db/migrate/20261104010000_create_travel_resume_actions.rb]
_,_,tracked=Open3.capture3('git','-C',root,'ls-files','--error-unmatch',*paths)
_,_,clean=Open3.capture3('git','-C',root,'diff','--quiet','HEAD','--',*paths)
abort 'Operator and migration must match committed source' unless tracked.success? && clean.success?
ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
c=ActiveRecord::Base.connection
c.execute("SET application_name='startrader_resume_audit_operator'")
c.execute("SET statement_timeout='60s'")
c.execute("SET lock_timeout='2s'")
c.execute('SET default_transaction_read_only=on') unless options[:apply]
abort 'Unexpected database; no migration attempted' unless c.select_value('SELECT current_database()')==options[:database]
versions=ActiveRecord::Base.connection_pool.schema_migration
expected=%w[20261101010000 20261101010100 20261101010200 20261101010300]
abort 'Travel lifecycle schema prerequisites missing' unless (expected-versions.versions).empty?
version='20261104010000'
ids=c.select_values('SELECT id FROM ship_travels ORDER BY id LIMIT 1001').map(&:to_i)
abort 'Protected snapshot exceeds bounded scope' if ids.size>1000
scope=ids.empty? ? 'NULL' : ids.join(',')
fingerprint=-> {
  ships="SELECT user_ship_id FROM ship_travels WHERE id IN (#{scope})"
  queries={
    travel:"SELECT row_to_json(x)::text body FROM ship_travels x WHERE id IN (#{scope}) ORDER BY id",
    ships:"SELECT row_to_json(x)::text body FROM user_ships x WHERE id IN (#{ships}) ORDER BY id",
    players:"SELECT row_to_json(x)::text body FROM shard_users x WHERE id IN (SELECT shard_user_id FROM user_ships WHERE id IN (#{ships})) ORDER BY id",
    cargo:"SELECT row_to_json(x)::text body FROM user_ship_cargos x WHERE user_ship_id IN (#{ships}) ORDER BY id"}
  queries.transform_values{|sql|Digest::SHA256.hexdigest(JSON.generate(c.select_values(sql)))}
}
report={at_utc:Time.now.utc.iso8601,source_sha:sha.strip,mode:options[:apply] ? 'apply' : 'dry_run',
 version:version,protected_ids:ids,action:versions.versions.include?(version) ? 'already_applied' : 'pending'}
ActiveRecord::Migration.verbose=false
ActiveRecord::Base.transaction do
  c.execute('SELECT pg_advisory_xact_lock(76532450)') if options[:apply]
  before=fingerprint.call
  if options[:apply] && !versions.versions.include?(version)
    abort 'Unversioned audit table already exists; review schema drift' if c.data_source_exists?('travel_resume_actions')
    CreateTravelResumeActions.new.migrate(:up)
    versions.create_version(version)
    report[:action]='applied'
  end
  if options[:apply]
    index=c.indexes(:travel_resume_actions).find{|i|i.name=='index_one_resume_action_per_interdiction'}
    valid=c.select_value("SELECT indisvalid AND indisready FROM pg_index WHERE indexrelid='index_one_resume_action_per_interdiction'::regclass")
    raise 'Audit uniqueness index is not valid' unless index&.unique && index.columns==%w[travel_guid interdiction_count] && valid
  end
  raise 'Protected travel resources changed during migration' unless before==fingerprint.call
  report[:protected_unchanged]=true
  report[:protected_hashes]=before
end
puts JSON.pretty_generate(report)
ActiveRecord::Base.connection_pool.disconnect!
