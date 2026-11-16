-- M09 preflight and post-release check (read-only, aggregate counts only).
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '20s';
SELECT 'casefold_shard_dupe_groups' AS metric, count(*)::text AS value FROM (SELECT lower(btrim(channel_uuid)) FROM shards WHERE channel_uuid IS NOT NULL GROUP BY 1 HAVING count(*) > 1) g
UNION ALL SELECT 'shards', count(*)::text FROM shards
UNION ALL SELECT 'unfinished_journeys', count(*)::text FROM ship_travels WHERE completed_at_tick IS NULL
UNION ALL SELECT 'paused_zero_journeys', count(*)::text FROM ship_travels WHERE completed_at_tick IS NULL AND is_paused AND arrival_tick = 0
UNION ALL SELECT 'ships_with_multiple_unfinished', count(*)::text FROM (SELECT user_ship_id FROM ship_travels WHERE completed_at_tick IS NULL GROUP BY 1 HAVING count(*) > 1) d
UNION ALL SELECT 'tick_current', (SELECT current_tick::text FROM ticks ORDER BY id LIMIT 1)
UNION ALL SELECT 'tick_running', (SELECT running::text FROM tick_controls ORDER BY id LIMIT 1)
UNION ALL SELECT 'tick_failure_count', (SELECT failure_count::text FROM tick_controls ORDER BY id LIMIT 1)
UNION ALL SELECT 'tick_last_completed_age_s', (SELECT round(extract(epoch FROM now() - last_tick_completed_at))::text FROM tick_controls ORDER BY id LIMIT 1)
UNION ALL SELECT 'failed_delayed_jobs', count(*)::text FROM delayed_jobs WHERE failed_at IS NOT NULL
UNION ALL SELECT 'pending_arrival_events', count(*)::text FROM travel_arrival_events WHERE sent_at IS NULL
UNION ALL SELECT 'shard_users', count(*)::text FROM shard_users
UNION ALL SELECT 'user_ships', count(*)::text FROM user_ships
UNION ALL SELECT 'users', count(*)::text FROM users
UNION ALL SELECT 'latest_migration', (SELECT max(version) FROM schema_migrations)
UNION ALL SELECT 'has_location_columns', (SELECT count(*)::text FROM information_schema.columns WHERE table_name = 'shard_users' AND column_name IN ('location_updated_at','location_source'))
UNION ALL SELECT 'read_only', current_setting('transaction_read_only');
ROLLBACK;
