-- M00 production read-only audit (decision P2: aggregate counts only, no identifiers).
-- Run: heroku pg:psql -a star-trader < docs/evidence/status-location-time/M00/prod_readonly_audit.sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '20s';

\echo '== A. shard_users.last_location storage type (F-07 / P-03)'
SELECT coalesce(jsonb_typeof(last_location), 'sql_null') AS stored_as, count(*) FROM shard_users GROUP BY 1 ORDER BY 1;

\echo '== B. decoded payload shape (P-02): named / coordinates / empty'
WITH decoded AS (
  SELECT CASE
           WHEN jsonb_typeof(last_location) = 'object' THEN last_location
           WHEN jsonb_typeof(last_location) = 'string' AND (last_location #>> '{}') LIKE '{%' THEN (last_location #>> '{}')::jsonb
         END AS p
  FROM shard_users)
SELECT count(*) FILTER (WHERE p IS NULL)                                   AS undecodable_or_null,
       count(*) FILTER (WHERE p = '{}'::jsonb)                              AS empty_object,
       count(*) FILTER (WHERE coalesce(p->>'name', p->>'location_name') IS NOT NULL) AS has_name,
       count(*) FILTER (WHERE p ? 'x' OR p ? 'y' OR p ? 'z')                AS has_coordinate_keys,
       count(*) FILTER (WHERE (p ? 'x') AND coalesce(p->>'name', p->>'location_name') IS NULL) AS coordinates_only
FROM decoded;

\echo '== C. case/whitespace-variant shard channel_uuid groups (F-04 / P-04)'
SELECT count(*) AS variant_groups, coalesce(sum(n), 0) AS shards_in_variant_groups FROM (
  SELECT lower(btrim(channel_uuid)) k, count(*) n FROM shards WHERE channel_uuid IS NOT NULL GROUP BY 1 HAVING count(*) > 1) g;
SELECT count(*) AS shards_total, count(*) FILTER (WHERE channel_uuid IS NULL) AS shards_without_uuid,
       count(*) FILTER (WHERE name LIKE 'Shard %') AS status_autocreated_name_pattern FROM shards;

\echo '== D. ship location names missing from the catalog (U-04)'
SELECT count(*) AS ships_total,
       count(*) FILTER (WHERE us.location_name IS NULL OR us.location_name = '') AS ship_location_blank,
       count(*) FILTER (WHERE us.location_name <> '' AND l.id IS NULL) AS ship_location_not_in_catalog,
       count(*) FILTER (WHERE us.shard_user_id IS NULL) AS ship_without_shard_user
FROM user_ships us LEFT JOIN locations l ON l.name = us.location_name;

\echo '== E. ship vs player divergence (P-05), split by unfinished journey'
WITH decoded AS (
  SELECT su.id, CASE WHEN jsonb_typeof(su.last_location)='object' THEN su.last_location
                     WHEN jsonb_typeof(su.last_location)='string' AND (su.last_location #>> '{}') LIKE '{%' THEN (su.last_location #>> '{}')::jsonb END AS p
  FROM shard_users su),
pairs AS (
  SELECT us.id, us.location_name AS ship_loc, coalesce(d.p->>'name', d.p->>'location_name') AS player_loc,
         EXISTS (SELECT 1 FROM ship_travels st WHERE st.user_ship_id = us.id AND st.completed_at_tick IS NULL) AS unfinished
  FROM user_ships us JOIN decoded d ON d.id = us.shard_user_id)
SELECT unfinished,
       count(*) AS pairs,
       count(*) FILTER (WHERE player_loc IS NULL) AS player_unknown,
       count(*) FILTER (WHERE player_loc IS NOT NULL AND ship_loc IS DISTINCT FROM player_loc) AS diverged,
       count(*) FILTER (WHERE player_loc IS NOT NULL AND ship_loc = player_loc) AS aligned
FROM pairs GROUP BY unfinished ORDER BY unfinished;

\echo '== F. N-01 impact: ships/players status-locked by receipts with no unfinished journey'
SELECT count(DISTINCT r.user_ship_id) AS ships_with_receipts,
       count(DISTINCT r.user_ship_id) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM ship_travels st WHERE st.user_ship_id = r.user_ship_id AND st.completed_at_tick IS NULL)) AS ships_locked_idle,
       count(DISTINCT us.shard_user_id) AS players_with_receipt_ships
FROM travel_request_receipts r LEFT JOIN user_ships us ON us.id = r.user_ship_id;
SELECT outcome, count(*) FROM travel_request_receipts GROUP BY 1 ORDER BY 1;

\echo '== G. unfinished journeys'
SELECT count(*) AS unfinished, count(*) FILTER (WHERE is_paused) AS paused,
       count(*) FILTER (WHERE is_paused AND arrival_tick = 0) AS paused_zero_sentinel,
       count(*) FILTER (WHERE ship_travel_type = 'gate_travel') AS gate
FROM ship_travels WHERE completed_at_tick IS NULL;

\echo '== H. identity integrity (section 9.3)'
SELECT count(*) AS duplicate_twitch_id_groups FROM (SELECT twitch_id FROM users WHERE twitch_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1) t;
SELECT count(*) AS users_total FROM users;

\echo '== I. schema migration markers'
SELECT version FROM schema_migrations WHERE version IN ('20261024170000','20261101010000','20261101010100','20261101010200','20261101010300','20261104010000') ORDER BY 1;
SELECT current_setting('transaction_read_only') AS read_only;
ROLLBACK;
