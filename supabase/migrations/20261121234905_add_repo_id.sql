-- Tie inventory rows to a repository, and backfill existing rows with the seeded
-- FWU-SOE repository (district 33).
--
-- ASSUMPTIONS (change to match your schema):
--   inventory_lots and inventory_reservations are tables
--   public.inventory_repositories and the FWU-SOE seed row exist (previous two migrations)
--
-- inventory_available is a VIEW, so it is not changed here. It gets the new column through
-- its own definition, in a separate migration (it reads the column from the tables below).

-- 1. New column on each table: nullable at first so existing rows are accepted.
alter table public.inventory_lots
  add column if not exists inventory_repository_id uuid
  references public.inventory_repositories (id) on delete restrict;

alter table public.inventory_reservations
  add column if not exists inventory_repository_id uuid
  references public.inventory_repositories (id) on delete restrict;

-- 2. Backfill every existing row with the seeded repository.
do $$
declare
  v_repo uuid;
begin
  select id into v_repo
    from public.inventory_repositories
   where district_id = 33
     and name = 'FWU-SOE';

  if v_repo is null then
    raise exception 'Seed repository FWU-SOE (district 33) not found: run the seed migration first';
  end if;

  update public.inventory_lots
     set inventory_repository_id = v_repo
   where inventory_repository_id is null;

  update public.inventory_reservations
     set inventory_repository_id = v_repo
   where inventory_repository_id is null;
end;
$$;

-- 3. Indexes for filtering and joining by repository.
create index if not exists inventory_lots_repository_idx
  on public.inventory_lots (inventory_repository_id);

create index if not exists inventory_reservations_repository_idx
  on public.inventory_reservations (inventory_repository_id);

-- 4. OPTIONAL, once everything that inserts into these tables supplies a repository:
--    make the column mandatory. Left off on purpose: it would make any insert that does
--    not yet send inventory_repository_id fail.
--
-- alter table public.inventory_lots         alter column inventory_repository_id set not null;
-- alter table public.inventory_reservations alter column inventory_repository_id set not null;