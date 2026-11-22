-- Inventory <-> repository sync.
--
-- Problem this fixes: the repository column exists on inventory_lots / inventory_reservations, but nothing
-- filled it for NEW rows (donation pickups, admin_import_stock, lot splits in admin_move_lot, reservations made
-- by admin_approve_request), and approvals reserved stock from any repository.
--
-- After this migration:
--   incoming  - every new lot gets a repository: the one passed in, else the repository nearest to the donation
--               request, else FWU-SOE. Splitting a lot keeps its repository.
--   outgoing  - a reservation always carries its lot's repository (trigger + composite foreign key, so the two
--               can never disagree). Approvals reserve from repositories in the request's district first.
--   ledger    - inventory_movements records the repository too.
--   checks    - inventory_available_by_repository (view) and admin_inventory_reconcile() (drift report).
-- Safe to run twice.

-- 1. Default repository ----------------------------------------------------------------------------------------
create or replace function public.default_inventory_repository_id()
returns uuid
language sql
stable
set search_path = public, extensions
as $$
  select id from public.inventory_repositories
   where district_id = 33 and name = 'FWU-SOE'
   limit 1;
$$;

-- 2. Ledger column ---------------------------------------------------------------------------------------------
alter table public.inventory_movements
  add column if not exists inventory_repository_id uuid
  references public.inventory_repositories (id) on delete restrict;

-- 3. Triggers that keep new rows in sync -----------------------------------------------------------------------
create or replace function public.fn_inventory_lot_set_repository()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.inventory_repository_id is null and new.source_request_id is not null then
    -- donation pickup: nearest repository to where the donation was collected
    select rp.id into new.inventory_repository_id
      from public.requests rq
      cross join lateral (
        select r.id from public.inventory_repositories r
         order by r.location operator(extensions.<->) rq.location
         limit 1
      ) rp
     where rq.id = new.source_request_id;
  end if;

  if new.inventory_repository_id is null then
    new.inventory_repository_id := public.default_inventory_repository_id();
  end if;

  if new.inventory_repository_id is null then
    raise exception 'no_default_repository';
  end if;
  return new;
end;
$$;

drop trigger if exists inventory_lots_set_repository on public.inventory_lots;
create trigger inventory_lots_set_repository
  before insert on public.inventory_lots
  for each row execute function public.fn_inventory_lot_set_repository();

-- Reservations and movements always take the repository of their lot, whatever the caller sent.
create or replace function public.fn_inventory_child_copy_repository()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  select l.inventory_repository_id into new.inventory_repository_id
    from public.inventory_lots l where l.id = new.lot_id;
  return new;
end;
$$;

drop trigger if exists inventory_reservations_copy_repository on public.inventory_reservations;
create trigger inventory_reservations_copy_repository
  before insert or update of lot_id, inventory_repository_id on public.inventory_reservations
  for each row execute function public.fn_inventory_child_copy_repository();

drop trigger if exists inventory_movements_copy_repository on public.inventory_movements;
create trigger inventory_movements_copy_repository
  before insert on public.inventory_movements
  for each row execute function public.fn_inventory_child_copy_repository();

-- 4. Backfill (rows created after the previous backfill migration) ----------------------------------------------
update public.inventory_lots
   set inventory_repository_id = public.default_inventory_repository_id()
 where inventory_repository_id is null;

update public.inventory_reservations r
   set inventory_repository_id = l.inventory_repository_id
  from public.inventory_lots l
 where l.id = r.lot_id
   and r.inventory_repository_id is distinct from l.inventory_repository_id;

update public.inventory_movements m
   set inventory_repository_id = l.inventory_repository_id
  from public.inventory_lots l
 where l.id = m.lot_id
   and m.inventory_repository_id is distinct from l.inventory_repository_id;

-- 5. Make it mandatory, and tie reservations to their lot's repository ------------------------------------------
alter table public.inventory_lots         alter column inventory_repository_id set not null;
alter table public.inventory_reservations alter column inventory_repository_id set not null;
alter table public.inventory_movements    alter column inventory_repository_id set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'inventory_lots_id_repository_key') then
    alter table public.inventory_lots
      add constraint inventory_lots_id_repository_key unique (id, inventory_repository_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'inventory_reservations_lot_repository_fkey') then
    alter table public.inventory_reservations
      add constraint inventory_reservations_lot_repository_fkey
      foreign key (lot_id, inventory_repository_id)
      references public.inventory_lots (id, inventory_repository_id);
  end if;
end;
$$;

create index if not exists inventory_movements_repository_idx
  on public.inventory_movements (inventory_repository_id);

-- 6. Per-repository availability (the old inventory_available view stays as is: the dashboard reads it) ---------
create or replace view public.inventory_available_by_repository
with (security_invoker = true) as
  select l.inventory_repository_id,
         r.name as repository_name,
         r.district_id,
         l.item_type,
         sum(l.quantity - l.reserved_qty) as available_qty
    from public.inventory_lots l
    join public.inventory_repositories r on r.id = l.inventory_repository_id
   where l.phase = 'ready_to_ship'
   group by l.inventory_repository_id, r.name, r.district_id, l.item_type;

revoke all on public.inventory_available_by_repository from anon, authenticated;

-- 7. Drift report ----------------------------------------------------------------------------------------------
-- Returns { ok, issues: [...] }. Empty issues means lots, reservations and repositories agree.
--   reserved_mismatch   : lot.reserved_qty differs from the sum of its active reservations
--   stale_reservation   : an active reservation whose request is already fulfilled, declined or cancelled
--   reservation_not_ready: an active reservation on a lot that is no longer ready_to_ship
create or replace function public.admin_inventory_reconcile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_issues jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select coalesce(jsonb_agg(x.j), '[]'::jsonb) into v_issues
    from (
      select jsonb_build_object(
               'type', 'reserved_mismatch', 'lot_id', l.id,
               'repository_id', l.inventory_repository_id,
               'reserved_qty', l.reserved_qty, 'active_reservations', coalesce(s.qty, 0)) as j
        from public.inventory_lots l
        left join (select lot_id, sum(quantity) as qty
                     from public.inventory_reservations where status = 'active' group by lot_id) s on s.lot_id = l.id
       where l.reserved_qty <> coalesce(s.qty, 0)
      union all
      select jsonb_build_object(
               'type', 'stale_reservation', 'reservation_id', r.id, 'lot_id', r.lot_id,
               'request_id', rq.id, 'request_status', rq.status)
        from public.inventory_reservations r
        join public.request_items i on i.id = r.request_item_id
        join public.requests rq on rq.id = i.request_id
       where r.status = 'active' and rq.status in ('fulfilled', 'declined', 'cancelled')
      union all
      select jsonb_build_object(
               'type', 'reservation_not_ready', 'reservation_id', r.id, 'lot_id', l.id, 'phase', l.phase)
        from public.inventory_reservations r
        join public.inventory_lots l on l.id = r.lot_id
       where r.status = 'active' and l.phase <> 'ready_to_ship'
    ) x;

  return jsonb_build_object('ok', jsonb_array_length(v_issues) = 0, 'issues', v_issues);
end;
$$;

revoke all on function public.admin_inventory_reconcile() from public, anon, authenticated;
grant execute on function public.admin_inventory_reconcile() to authenticated;
revoke all on function public.default_inventory_repository_id()      from public, anon, authenticated;
revoke all on function public.fn_inventory_lot_set_repository()       from public, anon, authenticated;
revoke all on function public.fn_inventory_child_copy_repository()    from public, anon, authenticated;
grant execute on function public.default_inventory_repository_id()    to service_role;

-- 8. RPCs that move stock, now repository-aware (bodies copied from migrations 3 and 7 with the changes marked) --
-- admin_import_stock: each row may carry "repository_id" (uuid, default FWU-SOE); error invalid_repository.
-- admin_move_lot: the lot created by a split keeps the source lot's repository.
-- admin_approve_request: reserves from the request's district first.

create or replace function public.admin_import_stock(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_el    jsonb;
  v_type  public.item_type;
  v_qty   numeric;
  v_unit  text;
  v_phase text;
  v_prov  text;
  v_cont  text;
  v_note  text;
  v_lot   uuid;
  v_repo  uuid;
  v_lots  jsonb := '[]'::jsonb;
  v_ids   uuid[] := '{}';
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'invalid_items';
  end if;

  for v_el in select e from jsonb_array_elements(p_items) e loop
    if jsonb_typeof(v_el) <> 'object' then raise exception 'invalid_items'; end if;

    begin
      v_type := (v_el->>'item_type')::public.item_type;
    exception when invalid_text_representation then
      raise exception 'invalid_items';
    end;
    if v_type is null then raise exception 'invalid_items'; end if;

    if jsonb_typeof(v_el->'qty') is distinct from 'number' then raise exception 'invalid_items'; end if;
    v_qty := round((v_el->>'qty')::numeric, 2);
    if v_qty <= 0 or v_qty > 1000000 then raise exception 'invalid_items'; end if;

    v_unit := coalesce(nullif(btrim(v_el->>'unit'), ''), 'unit');
    if char_length(v_unit) > 20 then raise exception 'invalid_items'; end if;

    v_phase := coalesce(nullif(btrim(v_el->>'phase'), ''), 'received');
    if v_phase not in ('received', 'processing', 'ready_to_ship') then raise exception 'invalid_phase'; end if;

    v_prov := nullif(btrim(coalesce(v_el->>'provider_name', '')), '');
    v_cont := nullif(btrim(coalesce(v_el->>'provider_contact', '')), '');
    v_note := nullif(btrim(coalesce(v_el->>'condition_note', '')), '');
    if char_length(coalesce(v_prov, '')) > 120 or char_length(coalesce(v_cont, '')) > 120
       or char_length(coalesce(v_note, '')) > 300 then
      raise exception 'invalid_items';
    end if;

    -- optional per-row repository_id; defaults to the FWU-SOE repository
    begin
      v_repo := coalesce(nullif(btrim(v_el->>'repository_id'), '')::uuid, public.default_inventory_repository_id());
    exception when invalid_text_representation then
      raise exception 'invalid_repository';
    end;
    if not exists (select 1 from public.inventory_repositories where id = v_repo) then
      raise exception 'invalid_repository';
    end if;

    insert into public.inventory_lots (item_type, unit, quantity, phase, provider_name, provider_contact, condition_note, created_by, inventory_repository_id)
    values (v_type, v_unit, v_qty, v_phase::public.inventory_phase, v_prov, v_cont, v_note, v_admin, v_repo)
    returning id into v_lot;

    insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id)
    values (v_lot, null, v_phase::public.inventory_phase, v_qty, 'stock import', v_admin);

    v_ids := v_ids || v_lot;
    v_lots := v_lots || jsonb_build_object(
      'id', v_lot, 'item_type', v_type, 'unit', v_unit, 'quantity', v_qty, 'phase', v_phase,
      'repository_id', v_repo
    );
  end loop;

  perform public.append_audit_log(
    'stock_imported', v_admin, 'inventory', null,
    jsonb_build_object('count', cardinality(v_ids), 'lot_ids', to_jsonb(v_ids))
  );

  return jsonb_build_object('lots', v_lots);
end;
$$;

create or replace function public.admin_move_lot(
  p_id uuid, p_phase text, p_qty numeric default null, p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := auth.uid();
  v_to      public.inventory_phase;
  v_lot     public.inventory_lots%rowtype;
  v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
  v_movable numeric;
  v_qty     numeric;
  v_target  uuid;
  v_split   boolean := false;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  begin
    v_to := p_phase::public.inventory_phase;
  exception when invalid_text_representation then
    raise exception 'invalid_phase';
  end;
  if v_to is null or v_to not in ('processing', 'ready_to_ship', 'adjusted') then
    raise exception 'invalid_phase';
  end if;

  if v_reason is not null and char_length(v_reason) > 300 then raise exception 'invalid_reason'; end if;
  if v_to = 'adjusted' and (v_reason is null or char_length(v_reason) < 2) then raise exception 'invalid_reason'; end if;

  select * into v_lot from public.inventory_lots where id = p_id for update;
  if not found then raise exception 'not_found'; end if;

  if not exists (
    select 1 from (values
      ('received',      'processing'),
      ('received',      'ready_to_ship'),
      ('received',      'adjusted'),
      ('processing',    'ready_to_ship'),
      ('processing',    'adjusted'),
      ('ready_to_ship', 'processing'),
      ('ready_to_ship', 'adjusted')
    ) t(f, s)
    where t.f = v_lot.phase::text and t.s = v_to::text
  ) then
    raise exception 'invalid_transition';
  end if;

  v_movable := v_lot.quantity - v_lot.reserved_qty;
  if v_movable <= 0 then raise exception 'lot_reserved'; end if;

  v_qty := coalesce(round(p_qty, 2), v_movable);
  if v_qty <= 0 or v_qty > v_movable then raise exception 'invalid_qty'; end if;

  if v_qty = v_lot.quantity then
    -- whole lot (nothing is reserved on it, otherwise v_qty could not equal quantity)
    update public.inventory_lots set phase = v_to, updated_at = now() where id = p_id;
    v_target := p_id;
  else
    update public.inventory_lots set quantity = quantity - v_qty, updated_at = now() where id = p_id;

    insert into public.inventory_lots (
      item_type, unit, quantity, phase, provider_name, provider_contact,
      source_request_id, condition_note, created_by, inventory_repository_id
    )
    values (
      v_lot.item_type, v_lot.unit, v_qty, v_to, v_lot.provider_name, v_lot.provider_contact,
      v_lot.source_request_id, v_lot.condition_note, v_admin, v_lot.inventory_repository_id
    )
    returning id into v_target;
    v_split := true;
  end if;

  insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id)
  values (v_target, v_lot.phase, v_to, v_qty, coalesce(v_reason, 'admin move'), v_admin);

  perform public.append_audit_log(
    'lot_moved', v_admin, 'lot', v_target,
    jsonb_build_object(
      'from', v_lot.phase, 'to', v_to, 'qty', v_qty,
      'source_lot_id', p_id, 'split', v_split, 'reason', v_reason,
      'repository_id', v_lot.inventory_repository_id
    )
  );

  return jsonb_build_object(
    'source_lot_id', p_id, 'lot_id', v_target, 'from_phase', v_lot.phase,
    'phase', v_to, 'qty', v_qty, 'split', v_split
  );
end;
$$;

create or replace function public.admin_approve_request(p_id uuid, p_items jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_req   public.requests%rowtype;
  v_item  record;
  v_lot   record;
  v_el    jsonb;
  v_want  numeric;
  v_left  numeric;
  v_free  numeric;
  v_take  numeric;
  v_total numeric := 0;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select * into v_req from public.requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_req.status <> 'pending_admin_review' then raise exception 'invalid_state'; end if;

  if v_req.kind in ('resource_request', 'donation_offer') then
    if p_items is not null then
      if jsonb_typeof(p_items) <> 'array' then raise exception 'invalid_items'; end if;
      if exists (
        select 1 from jsonb_array_elements(p_items) e
         where not exists (select 1 from public.request_items i
                            where i.request_id = p_id and i.id::text = e->>'item_id')
      ) then raise exception 'invalid_items'; end if;
      if (select count(distinct e->>'item_id') from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
        raise exception 'invalid_items';
      end if;
    end if;

    for v_item in
      select i.id, i.item_type, i.requested_qty
        from public.request_items i
       where i.request_id = p_id
       order by i.item_type, i.id
    loop
      v_want := v_item.requested_qty;

      if p_items is not null then
        select e into v_el from jsonb_array_elements(p_items) e where e->>'item_id' = v_item.id::text;
        if found then
          if jsonb_typeof(v_el->'approved_qty') is distinct from 'number' then raise exception 'invalid_items'; end if;
          v_want := (v_el->>'approved_qty')::numeric;
          if v_want < 0 or v_want > v_item.requested_qty then raise exception 'invalid_items'; end if;
        end if;
      end if;

      update public.request_items set approved_qty = v_want where id = v_item.id;
      v_total := v_total + v_want;

      if v_req.kind = 'resource_request' and v_want > 0 then
        v_left := v_want;
        -- Lock every candidate lot first, in one fixed order (created_at, id), so parallel approvals
        -- cannot deadlock even though the pick order below depends on the request's district.
        perform 1
           from public.inventory_lots l
          where l.phase = 'ready_to_ship' and l.item_type = v_item.item_type and l.quantity > l.reserved_qty
          order by l.created_at, l.id
            for update;

        -- Pick order: repositories in the request's own district first, then the rest; FIFO inside each group.
        for v_lot in
          select l.id
            from public.inventory_lots l
            join public.inventory_repositories rp on rp.id = l.inventory_repository_id
           where l.phase = 'ready_to_ship' and l.item_type = v_item.item_type and l.quantity > l.reserved_qty
           order by (rp.district_id = v_req.district_id) desc, l.created_at, l.id
        loop
          exit when v_left <= 0;
          select quantity - reserved_qty into v_free from public.inventory_lots where id = v_lot.id;
          continue when v_free <= 0;
          v_take := least(v_free, v_left);
          update public.inventory_lots
             set reserved_qty = reserved_qty + v_take, updated_at = now()
           where id = v_lot.id;
          insert into public.inventory_reservations (request_item_id, lot_id, quantity)
          values (v_item.id, v_lot.id, v_take);
          v_left := v_left - v_take;
        end loop;

        if v_left > 0 then
          raise exception 'insufficient_stock' using detail = v_item.item_type::text;
        end if;
      end if;
    end loop;

    if v_total <= 0 then raise exception 'nothing_approved'; end if;
  end if;

  update public.requests
     set status = 'approved', approved_at = now(), updated_at = now()
   where id = p_id;

  perform public.append_audit_log(
    'request_approved', v_admin, 'request', p_id,
    jsonb_build_object('kind', v_req.kind, 'public_ref', v_req.public_ref)
  );

  return jsonb_build_object(
    'request_id', p_id,
    'status', 'approved',
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'item_type', i.item_type, 'unit', i.unit,
        'requested_qty', i.requested_qty, 'approved_qty', i.approved_qty
      ) order by i.item_type, i.id), '[]'::jsonb)
      from public.request_items i where i.request_id = p_id
    )
  );
end;
$$;

-- Re-assert privileges (create or replace keeps them, this is belt and braces).
revoke all on function public.admin_import_stock(jsonb) from public, anon, authenticated;
revoke all on function public.admin_move_lot(uuid, text, numeric, text) from public, anon, authenticated;
revoke all on function public.admin_approve_request(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_import_stock(jsonb) to authenticated;
grant execute on function public.admin_move_lot(uuid, text, numeric, text) to authenticated;
grant execute on function public.admin_approve_request(uuid, jsonb) to authenticated;