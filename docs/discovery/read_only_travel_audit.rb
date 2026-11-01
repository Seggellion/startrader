require 'pg'
require 'json'
require 'open3'
require 'time'
def cli(*args)
 out,err,status=Open3.capture3({'HEROKU_SKIP_UPDATE_CHECK'=>'1'},'heroku',*args)
 raise "Heroku #{args.first} unavailable" unless status.success?
 out.strip
end
report={sampled_at:Time.now.utc.iso8601}
release=JSON.parse(cli('releases:info','--app','star-trader','--json'))
report[:release]=release.slice('version','status','created_at','id','slug')
c=PG.connect(cli('config:get','DATABASE_URL','--app','star-trader'),options:'-c default_transaction_read_only=on -c statement_timeout=10000 -c lock_timeout=2000',connect_timeout:10)
c.exec('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
queries={
 identity:"SELECT current_database(),current_setting('server_version') server_version,current_setting('transaction_read_only') read_only,now() snapshot_time",
 triggers:"SELECT tgname,pg_get_triggerdef(oid) definition FROM pg_trigger WHERE tgrelid='ship_travels'::regclass AND NOT tgisinternal",
 indexes:"SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' AND tablename='ship_travels' ORDER BY indexname",
 columns:"SELECT column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='ship_travels' ORDER BY ordinal_position",
 constraints:"SELECT conname,pg_get_constraintdef(oid) definition FROM pg_constraint WHERE conrelid='ship_travels'::regclass",
 tick:'SELECT id,current_tick,sequence,processed_at FROM ticks ORDER BY id LIMIT 5',
 settings:"SELECT key,value FROM settings WHERE key IN ('seconds_per_tick','hours_per_tick','interdiction_window_percent')",
 counts:"SELECT count(*) total,count(*) FILTER(WHERE arrival_tick=0) zero,count(*) FILTER(WHERE arrival_tick IS NULL) nulls,count(*) FILTER(WHERE arrival_tick<0) negative,count(*) FILTER(WHERE arrival_tick>0 AND arrival_tick<departure_tick) backwards FROM ship_travels",
 groups:"SELECT (arrival_tick=0) is_zero,is_paused,(completed_at_tick IS NOT NULL) completed,ship_travel_type,count(*),min(created_at) first_created,max(created_at) last_created,min(updated_at) first_updated,max(updated_at) last_updated FROM ship_travels GROUP BY 1,2,3,4 ORDER BY 1,2,3,4",
 sample:"SELECT t.*,s.location_name,s.status ship_status,s.shard_user_id,s.used_scu,s.total_scu,f.name origin,f.star_system_name origin_system,d.name destination,d.star_system_name destination_system FROM ship_travels t LEFT JOIN user_ships s ON s.id=t.user_ship_id LEFT JOIN locations f ON f.id=t.from_location_id LEFT JOIN locations d ON d.id=t.to_location_id ORDER BY (t.arrival_tick=0) DESC,t.id LIMIT 12",
 duplicates:'SELECT user_ship_id,count(*) FROM ship_travels WHERE completed_at_tick IS NULL GROUP BY user_ship_id HAVING count(*)>1 ORDER BY user_ship_id LIMIT 30',
 orphan:"SELECT count(*) FILTER(WHERE s.id IS NULL) missing_ship,count(*) FILTER(WHERE f.id IS NULL) missing_origin,count(*) FILTER(WHERE d.id IS NULL) missing_destination FROM ship_travels t LEFT JOIN user_ships s ON s.id=t.user_ship_id LEFT JOIN locations f ON f.id=t.from_location_id LEFT JOIN locations d ON d.id=t.to_location_id",
 overdue:"SELECT count(*) due FROM ship_travels WHERE NOT is_paused AND completed_at_tick IS NULL AND arrival_tick>0 AND arrival_tick<=(SELECT current_tick FROM ticks ORDER BY id LIMIT 1)",
 contradictions:"SELECT s.status,t.is_paused,(t.arrival_tick=0) is_zero,count(*) FROM ship_travels t JOIN user_ships s ON s.id=t.user_ship_id GROUP BY 1,2,3 ORDER BY 1,2,3",
 gateways:"SELECT id,name,star_system_name,classification,is_available,is_visible FROM locations WHERE name ILIKE '%gateway%' ORDER BY star_system_name,name LIMIT 80",
 players:"SELECT t.id,su.last_location,su.wallet_balance,(SELECT count(*) FROM user_ship_cargos c WHERE c.user_ship_id=s.id) cargo_rows FROM ship_travels t JOIN user_ships s ON s.id=t.user_ship_id LEFT JOIN shard_users su ON su.id=s.shard_user_id ORDER BY t.id LIMIT 12",
 timing_consistency:"SELECT count(*) FILTER(WHERE paused_at_tick+remaining_ticks_from_arrival=departure_tick+total_duration_ticks) matching_original_arrival,count(*) FILTER(WHERE paused_at_tick IS NULL OR remaining_ticks_from_arrival IS NULL OR remaining_ticks_from_arrival<0) bad_pause_fields FROM ship_travels WHERE arrival_tick=0",
 jobs:"SELECT count(*) total,count(*) FILTER(WHERE failed_at IS NOT NULL) failed,min(run_at),max(run_at) FROM delayed_jobs WHERE handler LIKE '%TickJob%'"
}
queries.each do |key,sql|
 begin
 c.exec('SAVEPOINT audit_query')
 report[key]=c.exec(sql).to_a
 c.exec('RELEASE SAVEPOINT audit_query')
 rescue PG::Error=>e
 c.exec('ROLLBACK TO SAVEPOINT audit_query')
 report[key]={error:e.message.lines.first.strip}
 end
end
c.exec('ROLLBACK');c.close
File.write('tmp/jump-travel-runtime.json',JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
