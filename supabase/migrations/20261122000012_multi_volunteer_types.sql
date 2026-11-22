-- One volunteer can be more than one type (for example driver AND doctor).
--
-- volunteer_applications.volunteer_types holds every type the applicant signed up for.
-- volunteer_applications.volunteer_type stays as the "primary" type (doctor > driver > manpower),
-- so profiles.volunteer_type, the admin dashboards and old clients keep working unchanged.
-- profiles.categories already is an array and is the source of truth for what a volunteer may do;
-- approve-volunteer now fills it with the union of the categories of all selected types.
-- Safe to run more than once.

-- 1. New column, backfilled from the single type every existing row already has.
alter table public.volunteer_applications
  add column if not exists volunteer_types public.volunteer_type[] not null default '{}';

update public.volunteer_applications
   set volunteer_types = array[volunteer_type]
 where cardinality(volunteer_types) = 0;

-- 2. Keep the two columns consistent for every writer (edge functions, seed scripts, SQL editor):
--    an empty list becomes {volunteer_type}, and the primary type is always part of the list.
create or replace function public.fn_volunteer_applications_sync_types()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.volunteer_types is null or cardinality(new.volunteer_types) = 0 then
    new.volunteer_types := array[new.volunteer_type];
  elsif not (new.volunteer_type = any (new.volunteer_types)) then
    new.volunteer_types := new.volunteer_types || new.volunteer_type;
  end if;
  return new;
end;
$$;

-- Trigger function: service_role only (see 20261122000011_function_privileges.sql).
revoke all on function public.fn_volunteer_applications_sync_types() from public, anon, authenticated;
grant execute on function public.fn_volunteer_applications_sync_types() to service_role;

drop trigger if exists trg_volunteer_applications_sync_types on public.volunteer_applications;
create trigger trg_volunteer_applications_sync_types
  before insert or update on public.volunteer_applications
  for each row execute function public.fn_volunteer_applications_sync_types();

-- 3. Replace the two old document checks (they looked at volunteer_type only, and were created unnamed
--    in 20261121000001_init.sql, so find them by what they test instead of by name).
do $$
declare
  c record;
begin
  for c in
    select con.conname
      from pg_constraint con
     where con.conrelid = 'public.volunteer_applications'::regclass
       and con.contype = 'c'
       and (pg_get_constraintdef(con.oid) like '%license_photo_path%'
            or pg_get_constraintdef(con.oid) like '%service_card_photo_path%')
  loop
    execute format('alter table public.volunteer_applications drop constraint %I', c.conname);
  end loop;
end
$$;

alter table public.volunteer_applications
  drop constraint if exists volunteer_applications_driver_docs_chk,
  drop constraint if exists volunteer_applications_doctor_docs_chk,
  drop constraint if exists volunteer_applications_types_chk;

alter table public.volunteer_applications
  add constraint volunteer_applications_types_chk
    check (cardinality(volunteer_types) >= 1 and volunteer_type = any (volunteer_types)),
  add constraint volunteer_applications_driver_docs_chk
    check (not ('driver'::public.volunteer_type = any (volunteer_types))
           or (license_no is not null and license_photo_path is not null)),
  add constraint volunteer_applications_doctor_docs_chk
    check (not ('doctor'::public.volunteer_type = any (volunteer_types))
           or (service_card_no is not null and service_card_photo_path is not null));