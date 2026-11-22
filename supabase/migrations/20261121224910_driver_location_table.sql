-- Driver live-location setup, in dependency order:
--   1. the driver_latest_location table
--   2. the assignment_current_event view (an assignment's state = its latest event)
--   3. a trigger on public.assignments that creates the location row
--   4. a one-time backfill for assignments that already exist
--
-- ASSUMPTIONS (change to match your schema):
--   public.assignments:         id (uuid), request_id, volunteer_id (the driver)
--   public.assignment_events: id, assignment_id, event_type, created_at
--   public.requests:           id, tracking_token_hash (the stored, hashed tracking value)
--   public.profiles:           id (uuid)

-- ============================================================================
-- 1. TABLE: one row per assignment, the driver's latest known position.
--    Written by Edge Functions (service role) only.
-- ============================================================================

create extension if not exists postgis with schema extensions;

create table if not exists public.driver_latest_location (
  assign_id       uuid primary key
                  references public.assignments (id) on delete cascade,
  volunteer_id    uuid not null
                  references public.profiles (id) on delete cascade,
  tracking_number text,                     -- stored (hashed) tracking value; null if the request has no token
  loc             extensions.geography(Point, 4326),  -- latest position; null until the driver's first ping
  updated_at      timestamptz               -- time of the last ping; null until the first ping
);

-- Pings look the row up by driver; token lookups go by tracking number.
create index if not exists driver_latest_location_volunteer_idx
  on public.driver_latest_location (volunteer_id);

-- Not unique: a request could in principle have more than one row sharing a tracking number.
create index if not exists driver_latest_location_tracking_idx
  on public.driver_latest_location (tracking_number);

-- No client access at all. Edge Functions use the service role, which bypasses RLS.
alter table public.driver_latest_location enable row level security;  -- no policies = deny
revoke all on public.driver_latest_location from anon, authenticated;

-- ============================================================================
-- 2. VIEW: public.assignments has no status column. An assignment's state is the type of
--    its most recent row in public.assignment_events (offered, accepted,
--    en_route_to_pickup, picked_up, en_route_to_destination, otp_verified).
-- ============================================================================

-- Speeds up "latest event per assignment".
create index if not exists assignments_events_latest_idx
  on public.assignment_events (assignment_id, created_at desc, id desc);

create or replace view public.assignment_current_event
with (security_invoker = true) as
select distinct on (e.assignment_id)
  e.assignment_id,
  a.request_id,
  a.volunteer_id,
  e.event_type,
  e.created_at as event_at
from public.assignment_events e
join public.assignments a on a.id = e.assignment_id
order by e.assignment_id, e.created_at desc, e.id desc;

-- Server-side only: no client access to assignment state through this view.
revoke all on public.assignment_current_event from anon, authenticated;

-- ============================================================================
-- 3. TRIGGER: keeps public.driver_latest_location in step with public.assignments.
--    - assignment inserted with a driver  -> location row created (no position yet)
--    - driver set or changed later        -> row created, or pointed at the new driver
--    - assignment has no driver (null)    -> nothing to create yet
--    The driver's first ping fills in the position.
-- ============================================================================

-- Remove the earlier version of this trigger, if an earlier run created it.
drop trigger if exists trg_assignment_create_driver_location on public.assignments;
drop function if exists public.fn_assignment_create_driver_location();

create or replace function public.fn_assignment_sync_driver_location()
returns trigger
language plpgsql
security definer          -- the table has no client access, so this must run as its owner
set search_path = public
as $$
begin
  -- An assignment can exist before any driver is chosen; there is nobody to track yet.
  if new.volunteer_id is null then
    return new;
  end if;

  insert into public.driver_latest_location (assign_id, volunteer_id, tracking_number)
  values (
    new.id,
    new.volunteer_id,
    (select r.tracking_token_hash from public.requests r where r.id = new.request_id)
  )
  on conflict (assign_id) do update
    set volunteer_id    = excluded.volunteer_id,
        tracking_number = excluded.tracking_number,
        -- a different driver must not inherit the previous driver's position
        loc        = case when public.driver_latest_location.volunteer_id
                                is distinct from excluded.volunteer_id
                          then null else public.driver_latest_location.loc end,
        updated_at = case when public.driver_latest_location.volunteer_id
                                is distinct from excluded.volunteer_id
                          then null else public.driver_latest_location.updated_at end;

  return new;
end;
$$;

drop trigger if exists trg_assignment_sync_driver_location on public.assignments;

-- AFTER: the foreign key needs the assignment row to exist first.
create trigger trg_assignment_sync_driver_location
after insert or update of volunteer_id on public.assignments
for each row execute function public.fn_assignment_sync_driver_location();

-- ============================================================================
-- 4. BACKFILL for assignments that already exist (safe to re-run).
--    Every assignment whose latest event is not otp_verified gets a row, including ones
--    that are only offered so far, so a driver who accepts later already has a row to ping.
-- ============================================================================

insert into public.driver_latest_location (assign_id, volunteer_id, tracking_number)
select a.id, a.volunteer_id, r.tracking_token_hash
  from public.assignments a
  left join public.requests r on r.id = a.request_id
  left join public.assignment_current_event c on c.assignment_id = a.id
 where a.volunteer_id is not null            -- skip assignments that have no driver yet
   and c.event_type is distinct from 'otp_verified'
on conflict (assign_id) do nothing;