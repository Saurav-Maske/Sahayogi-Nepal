-- Part 5: inventory, incidents and audit. Admin only: every function checks is_admin() first.
-- Lock order matches Parts 1 to 3: request row first, then assignment, then incident / lot rows.
-- Errors: forbidden | not_found | invalid_items | invalid_phase | invalid_transition | invalid_qty |
--   invalid_reason | lot_reserved | invalid_status | invalid_state | invalid_resolution | invalid_note |
--   invalid_limit

-- Adds stock. p_items: [{ "item_type": text, "qty": number, "unit"?: text, "phase"?: "received" |
-- "processing" | "ready_to_ship" (default received), "provider_name"?, "provider_contact"?, "condition_note"? }].
-- 1 to 50 rows. Each row becomes its own lot plus an inventory_movements row; the call is all-or-nothing and
-- writes one audit row. Only ready_to_ship stock can be reserved by admin_approve_request.
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

    insert into public.inventory_lots (item_type, unit, quantity, phase, provider_name, provider_contact, condition_note, created_by)
    values (v_type, v_unit, v_qty, v_phase::public.inventory_phase, v_prov, v_cont, v_note, v_admin)
    returning id into v_lot;

    insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id)
    values (v_lot, null, v_phase::public.inventory_phase, v_qty, 'stock import', v_admin);

    v_ids := v_ids || v_lot;
    v_lots := v_lots || jsonb_build_object(
      'id', v_lot, 'item_type', v_type, 'unit', v_unit, 'quantity', v_qty, 'phase', v_phase
    );
  end loop;

  perform public.append_audit_log(
    'stock_imported', v_admin, 'inventory', null,
    jsonb_build_object('count', cardinality(v_ids), 'lot_ids', to_jsonb(v_ids))
  );

  return jsonb_build_object('lots', v_lots);
end;
$$;

-- Moves a lot, or part of it, to another phase. Allowed moves:
--   received -> processing | ready_to_ship | adjusted
--   processing -> ready_to_ship | adjusted
--   ready_to_ship -> processing | adjusted      (only the part that is not reserved)
-- dispatched, consumed, returned and adjusted lots are system-managed and cannot be moved.
-- p_qty: how much to move, default all that is movable (quantity minus reserved). A partial move splits the
-- lot: the source keeps the rest, a new lot in the target phase receives p_qty (same item, provider, notes).
-- 'adjusted' is a write-off or correction and needs p_reason (2 to 300 characters).
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
      source_request_id, condition_note, created_by
    )
    values (
      v_lot.item_type, v_lot.unit, v_qty, v_to, v_lot.provider_name, v_lot.provider_contact,
      v_lot.source_request_id, v_lot.condition_note, v_admin
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
      'source_lot_id', p_id, 'split', v_split, 'reason', v_reason
    )
  );

  return jsonb_build_object(
    'source_lot_id', p_id, 'lot_id', v_target, 'from_phase', v_lot.phase,
    'phase', v_to, 'qty', v_qty, 'split', v_split
  );
end;
$$;

-- Incident queue for the admin panel: open first, then under_review, then closed ones, newest first (max 500).
-- p_status: optional filter, open | under_review | resolved | dismissed.
create or replace function public.admin_list_incidents(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if v_status is not null and v_status not in ('open', 'under_review', 'resolved', 'dismissed') then
    raise exception 'invalid_status';
  end if;

  return coalesce((
    select jsonb_agg(q.j order by q.rnk, q.created_at desc)
      from (
        select case i.status when 'open' then 0 when 'under_review' then 1 else 2 end as rnk,
               i.created_at,
               jsonb_build_object(
                 'id', i.id,
                 'status', i.status,
                 'incident_type', i.incident_type,
                 'reporter_note', i.reporter_note,
                 'reported_shortfall', i.reported_shortfall,
                 'resolution', i.resolution,
                 'admin_notes', i.admin_notes,
                 'created_at', i.created_at,
                 'request', case when r.id is not null then jsonb_build_object(
                     'id', r.id,
                     'public_ref', r.public_ref,
                     'kind', r.kind,
                     'status', r.status,
                     'requester_name', r.requester_name,
                     'requester_phone', r.requester_phone,
                     'district', d.name,
                     'items', (
                       select coalesce(jsonb_agg(jsonb_build_object(
                         'id', it.id, 'item_type', it.item_type, 'unit', it.unit,
                         'requested_qty', it.requested_qty, 'approved_qty', it.approved_qty,
                         'confirmed_qty', it.confirmed_qty
                       ) order by it.item_type, it.id), '[]'::jsonb)
                       from public.request_items it where it.request_id = r.id
                     )
                   ) end,
                 'assignment', case when a.id is not null then jsonb_build_object(
                     'id', a.id,
                     'assignment_type', a.assignment_type,
                     'state', a.state,
                     'volunteer_id', a.volunteer_id,
                     'volunteer_name', p.full_name,
                     'volunteer_phone', p.phone
                   ) end
               ) as j
          from public.incidents i
          left join public.requests r on r.id = i.request_id
          left join public.districts d on d.id = r.district_id
          left join public.assignments a on a.id = i.assignment_id
          left join public.profiles p on p.id = a.volunteer_id
         where v_status is null or i.status = v_status
         order by 1, i.created_at desc
         limit 500
      ) q
  ), '[]'::jsonb);
end;
$$;

-- Moves an incident forward: open -> under_review | resolved | dismissed, under_review -> resolved | dismissed.
-- resolved and dismissed are final and need p_resolution (2 to 500 characters). p_notes (max 1000) replaces
-- admin_notes when given.
-- Request effect: a dismissed incident (the report was not valid) puts a partially_fulfilled request back to
-- fulfilled once no other incident on it is still open. A resolved incident leaves it partially_fulfilled,
-- because the shortfall was real. The assignment stays disputed, which also stops a second report on it.
create or replace function public.admin_resolve_incident(
  p_id uuid, p_status text, p_resolution text default null, p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
  v_res    text := nullif(btrim(coalesce(p_resolution, '')), '');
  v_notes  text := nullif(btrim(coalesce(p_notes, '')), '');
  v_inc    public.incidents%rowtype;
  v_req_id uuid;
  v_open   int;
  v_reqst  public.request_status;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  if v_status not in ('under_review', 'resolved', 'dismissed') then raise exception 'invalid_status'; end if;
  if v_res is not null and char_length(v_res) > 500 then raise exception 'invalid_resolution'; end if;
  if v_status in ('resolved', 'dismissed') and (v_res is null or char_length(v_res) < 2) then
    raise exception 'invalid_resolution';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then raise exception 'invalid_note'; end if;

  select request_id into v_req_id from public.incidents where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if v_req_id is not null then
    perform 1 from public.requests where id = v_req_id for update;
  end if;

  select * into v_inc from public.incidents where id = p_id for update;
  if not found then raise exception 'not_found'; end if;

  if not ((v_inc.status = 'open' and v_status in ('under_review', 'resolved', 'dismissed'))
       or (v_inc.status = 'under_review' and v_status in ('resolved', 'dismissed'))) then
    raise exception 'invalid_state';
  end if;

  update public.incidents
     set status = v_status,
         resolution = coalesce(v_res, resolution),
         admin_notes = coalesce(v_notes, admin_notes)
   where id = p_id;

  if v_req_id is not null then
    if v_status = 'dismissed' then
      select count(*) into v_open from public.incidents
       where request_id = v_req_id and id <> p_id and status in ('open', 'under_review');
      if v_open = 0 then
        update public.requests set status = 'fulfilled', updated_at = now()
         where id = v_req_id and status = 'partially_fulfilled';
      end if;
    end if;
    select status into v_reqst from public.requests where id = v_req_id;
  end if;

  if v_inc.assignment_id is not null then
    insert into public.assignment_events (assignment_id, event_type, actor_id, payload)
    values (v_inc.assignment_id, 'incident_' || v_status, v_admin,
            jsonb_build_object('incident_id', p_id, 'resolution', v_res));
  end if;

  perform public.append_audit_log(
    'incident_' || v_status, v_admin, 'incident', p_id,
    jsonb_build_object('request_id', v_req_id, 'from', v_inc.status, 'to', v_status)
  );

  return jsonb_build_object(
    'id', p_id,
    'status', v_status,
    'resolution', coalesce(v_res, v_inc.resolution),
    'admin_notes', coalesce(v_notes, v_inc.admin_notes),
    'request_status', v_reqst
  );
end;
$$;

-- Audit timeline, newest first, keyset pagination. Send next_before back as p_before to get the next page
-- (null means there is no older row). p_limit 1 to 200 (default 100). Optional exact-match filters on action
-- and entity. Rows carry prev_hash and hash_value so the UI can show the chain; verification itself stays
-- with verify_audit_chain() (service role).
create or replace function public.admin_list_audit(
  p_limit int default 100, p_before bigint default null, p_action text default null, p_entity text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_limit  int := coalesce(p_limit, 100);
  v_action text := nullif(btrim(coalesce(p_action, '')), '');
  v_entity text := nullif(btrim(coalesce(p_entity, '')), '');
  v_rows   jsonb;
  v_next   bigint;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if v_limit not between 1 and 200 then raise exception 'invalid_limit'; end if;

  with page as (
    select l.*
      from public.audit_logs l
     where (p_before is null or l.id < p_before)
       and (v_action is null or l.action = v_action)
       and (v_entity is null or l.entity = v_entity)
     order by l.id desc
     limit v_limit + 1
  ), shown as (
    select * from page order by id desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'date', s.date,
           'action', s.action,
           'actor_id', s.actor_id,
           'actor_name', p.full_name,
           'entity', s.entity,
           'entity_id', s.entity_id,
           'detail', s.detail,
           'prev_hash', s.prev_hash,
           'hash_value', s.hash_value
         ) order by s.id desc), '[]'::jsonb),
         case when (select count(*) from page) > v_limit then (select min(id) from shown) end
    into v_rows, v_next
    from shown s
    left join public.profiles p on p.id = s.actor_id;

  return jsonb_build_object('items', v_rows, 'next_before', v_next);
end;
$$;

revoke all on function public.admin_import_stock(jsonb) from public, anon, authenticated;
revoke all on function public.admin_move_lot(uuid, text, numeric, text) from public, anon, authenticated;
revoke all on function public.admin_list_incidents(text) from public, anon, authenticated;
revoke all on function public.admin_resolve_incident(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.admin_list_audit(int, bigint, text, text) from public, anon, authenticated;

grant execute on function public.admin_import_stock(jsonb) to authenticated;
grant execute on function public.admin_move_lot(uuid, text, numeric, text) to authenticated;
grant execute on function public.admin_list_incidents(text) to authenticated;
grant execute on function public.admin_resolve_incident(uuid, text, text, text) to authenticated;
grant execute on function public.admin_list_audit(int, bigint, text, text) to authenticated;