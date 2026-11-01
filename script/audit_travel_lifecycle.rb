# Read-only, sanitized by default. No Rails boot, broker calls or repair mode.
require 'pg'
require 'json'
require 'time'
require 'open3'
require_relative '../lib/travel_state_contract'
app=ARGV[ARGV.index('--heroku-app').to_i+1] if ARGV.include?('--heroku-app')
if app
  raise 'Unexpected app' unless app=='star-trader'
  url,_,status=Open3.capture3({'HEROKU_SKIP_UPDATE_CHECK'=>'1'},'heroku','config:get','DATABASE_URL','--app',app)
  raise 'Database credential lookup unavailable' unless status.success?
  url=url.strip
else
  url=ENV.fetch('DATABASE_URL')
end
c=PG.connect(url,options:'-c default_transaction_read_only=on -c statement_timeout=10000 -c lock_timeout=2000',connect_timeout:10)
c.type_map_for_results=PG::BasicTypeMapForResults.new(c)
c.exec('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
tick=c.exec('SELECT current_tick FROM ticks ORDER BY id LIMIT 1').first&.fetch('current_tick') || 0
count=c.exec('SELECT count(*) n FROM ship_travels WHERE completed_at_tick IS NULL').first.fetch('n')
timing=c.exec("SELECT count(*) total,count(*) FILTER(WHERE arrival_tick=0) zero,count(*) FILTER(WHERE arrival_tick IS NULL) null_arrival,count(*) FILTER(WHERE arrival_tick<0) negative_arrival,count(*) FILTER(WHERE completed_at_tick IS NOT NULL AND arrival_tick=0) completed_zero FROM ship_travels").first
# Explicit bound; aggregate counts remain complete, records are a bounded sample.
rows=c.exec(<<~SQL).to_a
  SELECT t.*,s.status ship_status,s.location_name, su.last_location,
    (SELECT count(*) FROM ship_travels t2 WHERE t2.user_ship_id=t.user_ship_id AND t2.completed_at_tick IS NULL) unfinished_count,
    (SELECT count(*) FROM user_ship_cargos cargo WHERE cargo.user_ship_id=s.id) cargo_rows
  FROM ship_travels t
  LEFT JOIN user_ships s ON s.id=t.user_ship_id
  LEFT JOIN shard_users su ON su.id=s.shard_user_id
  WHERE t.completed_at_tick IS NULL ORDER BY t.id LIMIT 1000
SQL
records=rows.map do |r|
  location=r['last_location']
  4.times do
    break unless location.is_a?(String)
    location=JSON.parse(location) rescue nil
  end
  name=location.is_a?(Hash) ? location['name'] || location['location_name'] : nil
  state=r['unfinished_count']>1 ? 'invalid' : TravelStateContract.state(r,tick)
  warnings=[]
  warnings << 'invalid_unpaused_zero' if r['arrival_tick']==0 && !r['is_paused']
  warnings << 'malformed_pause_metadata' if r['is_paused'] && !TravelStateContract.valid_pause?(r)
  warnings << 'negative_or_missing_timing' if r['arrival_tick'].nil? || r['arrival_tick'].to_i<0 || r['departure_tick'].nil?
  warnings << 'duplicate_unfinished' if r['unfinished_count']>1
  warnings << 'ship_status_discrepancy' if r['ship_status'] != (r['is_paused'] ? 'interdicted' : 'in_transit')
  warnings << 'player_location_discrepancy' if name && name != r['location_name']
  warnings << 'missing_ship' unless r['ship_status']
  {travel_id:r['id'],ship_id:r['user_ship_id'],state:state,warnings:warnings,cargo_rows:r['cargo_rows'],
    broker:r['rabbitmq_environment'],arrival_tick:r['arrival_tick'],remaining_ticks:r['remaining_ticks_from_arrival'],
    proposed_action:state=='invalid' || warnings.any? ? 'review_only_no_mutation' : 'no_action'}
end
orphans=c.exec("SELECT count(*) FILTER(WHERE s.id IS NULL) missing_ship,count(*) FILTER(WHERE f.id IS NULL) missing_origin,count(*) FILTER(WHERE d.id IS NULL) missing_destination FROM ship_travels t LEFT JOIN user_ships s ON s.id=t.user_ship_id LEFT JOIN locations f ON f.id=t.from_location_id LEFT JOIN locations d ON d.id=t.to_location_id").first
notifications=if c.exec("SELECT to_regclass('public.travel_arrival_events') present").first['present']
 c.exec("SELECT count(*) FILTER(WHERE sent_at IS NULL) pending,count(*) FILTER(WHERE sent_at IS NULL AND last_error_class IS NOT NULL) retrying FROM travel_arrival_events").first
else
 {schema:'outbox_not_deployed'}
end
report={at_utc:Time.now.utc.iso8601,dry_run:true,read_only:c.exec('SHOW transaction_read_only').first.values.first,
 tick:tick,timing_counts:timing,total_unfinished:count,sample_limit:1000,truncated:count>1000,
 sample_state_counts:records.group_by{|r|r[:state]}.transform_values(&:size),records:records,orphan_reference_counts:orphans,notifications:notifications}
c.exec('ROLLBACK');c.close
puts JSON.pretty_generate(report)
