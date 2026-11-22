-- Switch the pilot district from Kathmandu to Kanchanpur.
--
-- The seed (20261122000001_seed_app_settings.sql) inserts Kathmandu with ON CONFLICT DO NOTHING, so this
-- migration runs after it and overwrites the value. It is an upsert, so it also works if the 'district'
-- row was deleted by hand.
--
-- Read by: submit_request RPC (value->'bounds' = service-area check) and the app's map (center, zoom).
-- Bounds are approximate (taken from the district's published latitude/longitude extent); after the
-- districts seed has run, compare them with the stored border (see the query at the bottom) and adjust.

insert into public.app_settings (key, value) values (
  'district',
  '{"name":"Kanchanpur","center":{"lat":28.97,"lng":80.18},"bounds":{"south":28.63,"west":80.05,"north":29.47,"east":80.55},"zoom":10}'::jsonb
) on conflict (key) do update set value = excluded.value;

-- Check afterwards (run by hand once the districts seed has loaded the borders):
--   select name,
--          st_ymin(geom::geometry) as south, st_xmin(geom::geometry) as west,
--          st_ymax(geom::geometry) as north, st_xmax(geom::geometry) as east
--   from public.districts where name ilike 'kanchanpur';