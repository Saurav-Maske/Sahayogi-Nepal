-- Inventory repositories: physical places where inventory is kept, each in one district.
--
-- ASSUMPTIONS (change to match your schema):
--   public.districts.id is an integer (the district you seed below is id 33)

create extension if not exists postgis with schema extensions;

create table if not exists public.inventory_repositories (
  id          uuid primary key default gen_random_uuid(),
  district_id integer not null
              references public.districts (id) on delete restrict,  -- a district with repositories can't be deleted
  name        text not null,
  location    extensions.geography(Point, 4326) not null            -- longitude first, then latitude
);

create index if not exists inventory_repositories_district_idx
  on public.inventory_repositories (district_id);

-- Spatial index, for "nearest repository" and "within X km" queries.
create index if not exists inventory_repositories_location_gix
  on public.inventory_repositories using gist (location);

-- No client access by default. Edge Functions use the service role, which bypasses RLS.
alter table public.inventory_repositories enable row level security;  -- no policies = deny
revoke all on public.inventory_repositories from anon, authenticated;

-- District 33 normally comes from supabase/seeds/nepal_districts.sql, but the seed runs after all migrations,
-- so on an empty database the foreign key below would fail. Create the row here; the seed fills in the border later.
insert into public.districts (id, name, province)
values (33, 'KANCHANPUR', 'Sudurpashchim Province')
on conflict do nothing;

-- Seed the FWU-SOE inventory repository (district 33).
-- Requires: public.inventory_repositories (previous migration) and a districts row with id 33.
--
-- Coordinates were given as "28.954657907336678, 80.17888176615499" (latitude, longitude).
-- PostGIS wants longitude first, so they are passed to st_makepoint as (lon, lat).

insert into public.inventory_repositories (district_id, name, location)
select 33,
       'FWU-SOE',
       extensions.st_setsrid(
         extensions.st_makepoint(80.17888176615499, 28.954657907336678),
         4326
       )::extensions.geography
where not exists (          -- safe to run twice
  select 1
    from public.inventory_repositories
   where district_id = 33
     and name = 'FWU-SOE'
);