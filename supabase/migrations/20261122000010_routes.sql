-- Saved routes for the get-route Edge Function (save: true). Closes the "routes table" gap (issue 7).
-- Rows are written only by the function with the service role. Clients can read their own rows; admins read all.

create table if not exists routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  assignment_id uuid references assignments(id) on delete set null,
  origin_lat double precision not null check (origin_lat between -90 and 90),
  origin_lon double precision not null check (origin_lon between -180 and 180),
  dest_lat double precision not null check (dest_lat between -90 and 90),
  dest_lon double precision not null check (dest_lon between -180 and 180),
  costing text not null check (costing in ('auto', 'bicycle', 'pedestrian', 'motorcycle')),
  distance_km double precision,
  duration_sec double precision,
  shape text not null,                       -- first leg, encoded polyline (precision 6)
  legs jsonb not null default '[]',          -- every leg: [{ shape, length, time }]
  created_at timestamptz not null default now()
);

create index if not exists routes_user_idx on routes (user_id, created_at desc);
create index if not exists routes_assignment_idx on routes (assignment_id) where assignment_id is not null;

alter table routes enable row level security;

drop policy if exists routes_read on routes;
create policy routes_read on routes for select using (user_id = auth.uid() or is_admin());

revoke all on routes from public, anon, authenticated;
grant select on routes to authenticated;