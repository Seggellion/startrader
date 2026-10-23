-- Narrow inverse of orbital_identity_repair.sql. Does not restore a database
-- or change updated_at, orbital fields, locations, or travel state.
BEGIN;
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO STRICT r FROM locations WHERE id=1366 FOR UPDATE;
  IF r.name IS DISTINCT FROM 'ArcCorp' OR r.classification IS DISTINCT FROM 'planet' OR
     r.star_system_name IS DISTINCT FROM 'Stanton' OR r.parent_name IS DISTINCT FROM 'Stanton' OR
     r.id_star_system IS DISTINCT FROM 68 OR r.code IS DISTINCT FROM 'ARC' THEN
    RAISE EXCEPTION 'ArcCorp rollback identity changed';
  END IF;
  IF r.api_id=4 THEN
    UPDATE locations SET api_id=NULL WHERE id=1366 AND api_id=4;
  ELSIF r.api_id IS NOT NULL THEN
    RAISE EXCEPTION 'ArcCorp external identity changed since calibration';
  END IF;
END $$;
COMMIT;
