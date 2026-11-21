-- When a row is inserted into public.assignment, create the matching row in
-- public.driver_latest_location (no position yet; the driver's first ping fills it in).
--
-- ASSUMPTIONS (change to match your schema):
--   public.assignment:  id, request_id, volunteer_id (the driver)
--   public.assignment_current_event: the view from the previous migration
--   public.requests:    id, tracking_token (the stored, hashed tracking value)

-- A request without a tracking token must not block the assignment, so allow a null here.
-- (Dropping NOT NULL on a column that is already nullable is harmless.)
alter table public.driver_latest_location
  alter column tracking_number drop not null;

create or replace function public.fn_assignment_create_driver_location()
returns trigger
language plpgsql
security definer          -- the table has no client access, so this must run as its owner
set search_path = public
as $$
begin
  insert into public.driver_latest_location (assign_id, volunteer_id, tracking_number)
  values (
    new.id,
    new.volunteer_id,
    (select r.tracking_token from public.requests r where r.id = new.request_id)
  )
  on conflict (assign_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_assignment_create_driver_location on public.assignment;

-- AFTER insert: the foreign key needs the assignment row to exist first.
create trigger trg_assignment_create_driver_location
after insert on public.assignment
for each row execute function public.fn_assignment_create_driver_location();

-- One-time backfill for assignments that already exist (safe to re-run).
-- Every assignment whose latest event is not otp_verified gets a row, including ones that
-- are only offered so far, so a driver who accepts later already has a row to ping.
insert into public.driver_latest_location (assign_id, volunteer_id, tracking_number)
select a.id, a.volunteer_id, r.tracking_token
  from public.assignment a
  left join public.requests r on r.id = a.request_id
  left join public.assignment_current_event c on c.assignment_id = a.id
 where c.event_type is distinct from 'otp_verified'
on conflict (assign_id) do nothing;


-- public.assignment has no status column. An assignment's state is the type of its most
-- recent row in public.assignments_events (offered, accepted, en_route_to_pickup,
-- picked_up, en_route_to_destination, otp_verified).
--
-- This view returns that latest event for every assignment, together with the request and
-- the driver the assignment belongs to, so Edge Functions can ask "is this assignment live?"
-- with one query.
--
-- ASSUMPTIONS (change to match your schema):
--   public.assignments_events:  id, assignment_id, event_type, created_at
--   public.assignment:          id, request_id, volunteer_id

-- Speeds up "latest event per assignment".
create index if not exists assignments_events_latest_idx
  on public.assignments_events (assignment_id, created_at desc, id desc);

create or replace view public.assignment_current_event
with (security_invoker = true) as
select distinct on (e.assignment_id)
  e.assignment_id,
  a.request_id,
  a.volunteer_id,
  e.event_type,
  e.created_at as event_at
from public.assignments_events e
join public.assignment a on a.id = e.assignment_id
order by e.assignment_id, e.created_at desc, e.id desc;

-- Server-side only: no client access to assignment state through this view.
revoke all on public.assignment_current_event from anon, authenticated;