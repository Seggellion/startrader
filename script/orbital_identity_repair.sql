-- Reviewed production before-image: Location 1366 api_id=NULL.
-- Source identity 4 is independently present on local ArcCorp; all canonical
-- name/classification/system/code preconditions must match before any write.
BEGIN;
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO STRICT r FROM locations WHERE id=1366 FOR UPDATE;
  IF r.name IS DISTINCT FROM 'ArcCorp' OR r.classification IS DISTINCT FROM 'planet' OR
     r.star_system_name IS DISTINCT FROM 'Stanton' OR r.parent_name IS DISTINCT FROM 'Stanton' OR
     r.id_star_system IS DISTINCT FROM 68 OR r.code IS DISTINCT FROM 'ARC' THEN
    RAISE EXCEPTION 'ArcCorp identity precondition changed';
  END IF;
  IF EXISTS (SELECT 1 FROM locations WHERE id<>1366 AND api_id=4
      AND classification='planet' AND star_system_name='Stanton') THEN
    RAISE EXCEPTION 'Duplicate ArcCorp external identity';
  END IF;
  IF r.api_id IS NULL THEN
    UPDATE locations SET api_id=4 WHERE id=1366 AND api_id IS NULL;
  ELSIF r.api_id <> 4 THEN
    RAISE EXCEPTION 'ArcCorp external identity changed';
  END IF;
END $$;
COMMIT;
