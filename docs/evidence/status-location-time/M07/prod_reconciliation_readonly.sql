-- M07 read-only reconciliation sizing (decision P2: aggregate counts only, no identifiers).
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '20s';
\echo '== diverged idle pairs, split by whether the ship has travel receipts and by multi-ship players'
WITH decoded AS (
  SELECT su.id, CASE WHEN jsonb_typeof(su.last_location)='object' THEN su.last_location
                     WHEN jsonb_typeof(su.last_location)='string' AND (su.last_location #>> '{}') LIKE '{%' THEN (su.last_location #>> '{}')::jsonb END AS p
  FROM shard_users su),
multi AS (SELECT shard_user_id FROM user_ships GROUP BY 1 HAVING count(*) > 1),
pairs AS (
  SELECT us.id, us.shard_user_id,
         EXISTS (SELECT 1 FROM travel_request_receipts r WHERE r.user_ship_id = us.id) AS has_receipts,
         us.shard_user_id IN (SELECT shard_user_id FROM multi) AS multi_ship_player
  FROM user_ships us JOIN decoded d ON d.id = us.shard_user_id
  WHERE NOT EXISTS (SELECT 1 FROM ship_travels st WHERE st.user_ship_id = us.id AND st.completed_at_tick IS NULL)
    AND coalesce(d.p->>'name', d.p->>'location_name') IS NOT NULL
    AND us.location_name IS DISTINCT FROM coalesce(d.p->>'name', d.p->>'location_name'))
SELECT has_receipts, multi_ship_player, count(*) AS diverged_pairs, count(DISTINCT shard_user_id) AS players
FROM pairs GROUP BY 1, 2 ORDER BY 1, 2;
\echo '== players with more than one ship'
SELECT count(*) AS players_with_multiple_ships FROM (SELECT shard_user_id FROM user_ships GROUP BY 1 HAVING count(*) > 1) t;
\echo '== unfinished journeys'
SELECT count(*) AS unfinished, count(*) FILTER (WHERE is_paused AND arrival_tick = 0) AS paused_zero FROM ship_travels WHERE completed_at_tick IS NULL;
SELECT current_setting('transaction_read_only') AS read_only;
ROLLBACK;
