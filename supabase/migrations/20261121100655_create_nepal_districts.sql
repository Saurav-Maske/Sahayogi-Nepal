-- 1. Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
SET search_path TO public, extensions;

alter table public.requests
  add column if not exists district_id int references public.districts(id);

alter table public.requests
  alter column district_id drop not null;


-- 2. Upgrade existing districts table to hold PostGIS borders
ALTER TABLE public.districts
  ADD COLUMN IF NOT EXISTS geom GEOMETRY(MultiPolygon, 4326);

ALTER TABLE public.districts
  DROP COLUMN IF EXISTS lat,
  DROP COLUMN IF EXISTS lng;

CREATE INDEX IF NOT EXISTS districts_geom_idx
  ON public.districts USING GIST (geom);

-- 3. Enable RLS (read-only metadata; heavy geom stays hidden from direct dumps if desired, or public read)
ALTER TABLE public.districts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read access to districts" ON public.districts;
CREATE POLICY "Allow public read access to districts"
  ON public.districts
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- 4. Auto-assign requests.district_id from requests.location
CREATE OR REPLACE FUNCTION public.auto_assign_request_district_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.location IS NOT NULL THEN
    SELECT d.id
    INTO NEW.district_id
    FROM public.districts d
    WHERE d.geom IS NOT NULL
      AND ST_Covers(d.geom, ST_SetSRID(NEW.location::geometry, 4326))
    LIMIT 1;
  ELSE
    NEW.district_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_assign_request_district ON public.requests;
CREATE TRIGGER trg_auto_assign_request_district
  BEFORE INSERT OR UPDATE OF location ON public.requests
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_request_district_id();
