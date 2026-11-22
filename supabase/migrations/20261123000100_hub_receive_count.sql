-- Phase 3a: the hub counts the donation, and stock is created from the count (not at pickup).
--
-- Before: driver_verify_otp (pickup) created the inventory lots from the driver's confirmed quantities.
-- Now:    the driver's pickup OTP only records what the driver confirmed (request_items.confirmed_qty) and the
--         job is picked_up (in transit). The admin counts at the hub with admin_receive_donation, which creates
--         the lots in phase 'received' plus their movements, and opens a hub_shortfall incident when the
--         counted number differs from what the driver confirmed.
--
-- Donations picked up before this migration already have lots (movement reason 'donation pickup'). They are left
-- alone: admin_receive_donation refuses them with already_received.
--
-- Raised errors: forbidden | not_found | invalid_state | invalid_items | invalid_quantity | already_received
-- Safe to run more than once (all objects are create or replace).

-- 1. True once the hub count of this pickup job is done (new flow) or its lots already exist (old flow).
create or replace function public._hub_counted(p_assignment uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (select 1 from public.assignment_events e
                  where e.assignment_id = p_assignment and e.event_type = 'hub_received')
      or exists (select 1 from public.inventory_movements m
                  where m.assignment_id = p_assignment and m.reason = 'donation pickup');
$$;

revoke all on function public._hub_counted(uuid) from public, anon, authenticated;
grant execute on function public._hub_counted(uuid) to service_role;

-- 2. driver_verify_otp: pickup no longer creates stock. (hub_dropoff comes in 3b.)
-- Pickup records what the driver confirmed and puts the job in transit; stock is created at the hub count.
-- p_confirmed matters only for pickup: the donor lowered a quantity, and the driver must accept the new
-- quantities by sending p_confirmed = true. Without it the call returns reason quantity_changed and the code
-- stays unused.
create or replace function public.driver_verify_otp(
  p_id uuid, p_purpose text, p_code text, p_confirmed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid     uuid := auth.uid();
  v_p       public.profiles%rowtype;
  v_a       public.assignments%rowtype;
  v_req     public.requests%rowtype;
  v_ch      public.otp_challenges%rowtype;
  v_req_id  uuid;
  v_code    text := regexp_replace(coalesce(p_code, ''), '\s', '', 'g');
  v_changed boolean := false;
  v_res     record;
  v_total   numeric := 0;
  v_items   jsonb;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;
  if p_purpose is null or p_purpose not in ('pickup', 'delivery') then raise exception 'invalid_purpose'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_req from public.requests where id = v_req_id for update;
  select * into v_a from public.assignments where id = p_id for update;
  if v_a.volunteer_id is distinct from v_uid then raise exception 'not_found'; end if;
  if v_a.assignment_type::text <> p_purpose then raise exception 'invalid_purpose'; end if;

  if v_req.status not in ('assigned', 'in_progress')
     or (p_purpose = 'pickup' and v_a.state not in ('accepted', 'en_route_to_pickup'))
     or (p_purpose = 'delivery' and v_a.state not in ('picked_up', 'en_route_to_destination')) then
    raise exception 'invalid_state';
  end if;

  select * into v_ch from public.otp_challenges
   where assignment_id = p_id and purpose = p_purpose
   order by created_at desc, id
   limit 1
   for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'otp_not_issued'); end if;
  if v_ch.consumed_at is not null then return jsonb_build_object('ok', false, 'reason', 'otp_used'); end if;
  if v_ch.expires_at <= now() then return jsonb_build_object('ok', false, 'reason', 'otp_expired'); end if;
  if v_ch.attempts >= 5 then return jsonb_build_object('ok', false, 'reason', 'otp_locked', 'attempts_left', 0); end if;

  if crypt(v_code, v_ch.code_hash) is distinct from v_ch.code_hash then
    update public.otp_challenges set attempts = attempts + 1 where id = v_ch.id;
    if v_ch.attempts + 1 >= 5 then
      perform public.append_audit_log('otp_locked', v_uid, 'assignment', p_id, jsonb_build_object('purpose', p_purpose));
      return jsonb_build_object('ok', false, 'reason', 'otp_locked', 'attempts_left', 0);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'invalid_otp', 'attempts_left', 5 - (v_ch.attempts + 1));
  end if;

  if p_purpose = 'pickup' then
    select exists (
      select 1 from public.request_items i
       where i.request_id = v_req_id and i.donor_qty is not null
         and i.donor_qty <> coalesce(i.approved_qty, i.requested_qty)
    ) into v_changed;

    if v_changed and not coalesce(p_confirmed, false) then
      return jsonb_build_object('ok', false, 'reason', 'quantity_changed', 'items', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'item_id', i.id, 'item_type', i.item_type, 'unit', i.unit,
          'expected_qty', coalesce(i.approved_qty, i.requested_qty),
          'qty', coalesce(i.donor_qty, i.approved_qty, i.requested_qty)
        ) order by i.item_type, i.id), '[]'::jsonb)
        from public.request_items i where i.request_id = v_req_id
      ));
    end if;

    update public.otp_challenges set consumed_at = now() where id = v_ch.id;

    update public.request_items
       set confirmed_qty = coalesce(donor_qty, approved_qty, requested_qty)
     where request_id = v_req_id;

    -- No stock is created here. The hub counts the kits and admin_receive_donation creates the lots.
    select coalesce(sum(i.confirmed_qty), 0) into v_total
      from public.request_items i where i.request_id = v_req_id and i.confirmed_qty > 0;
    if v_total <= 0 then raise exception 'nothing_to_pick_up'; end if;

    update public.assignments set state = 'picked_up' where id = p_id;
    update public.requests
       set picked_up_at = now(), updated_at = now(),
           status = case when status = 'assigned' then 'in_progress'::request_status else status end
     where id = v_req_id;

    insert into public.assignment_events (assignment_id, event_type, actor_id, payload) values
      (p_id, 'otp_verified', v_uid, jsonb_build_object('purpose', 'pickup', 'quantity_changed', v_changed)),
      (p_id, 'picked_up', v_uid, jsonb_build_object('qty', v_total));

    perform public.append_audit_log(
      'pickup_confirmed', v_uid, 'assignment', p_id,
      jsonb_build_object('request_id', v_req_id, 'quantity_changed', v_changed)
    );

    select coalesce(jsonb_agg(jsonb_build_object('item_type', i.item_type, 'qty', i.confirmed_qty, 'unit', i.unit)
                              order by i.item_type, i.id), '[]'::jsonb)
      into v_items
      from public.request_items i where i.request_id = v_req_id and i.confirmed_qty > 0;

    return jsonb_build_object('ok', true, 'state', 'picked_up', 'quantity_changed', v_changed, 'items', v_items);
  end if;

  -- delivery
  update public.otp_challenges set consumed_at = now() where id = v_ch.id;

  for v_res in
    select r.id as res_id, r.lot_id, r.quantity as qty
      from public.inventory_reservations r
      join public.request_items i on i.id = r.request_item_id
      join public.inventory_lots l on l.id = r.lot_id
     where i.request_id = v_req_id and r.status = 'active'
     order by l.created_at, l.id, r.id
       for update of l, r
  loop
    update public.inventory_lots
       set quantity = quantity - v_res.qty,
           reserved_qty = reserved_qty - v_res.qty,
           phase = case when quantity - v_res.qty = 0 then 'consumed'::inventory_phase else phase end,
           updated_at = now()
     where id = v_res.lot_id;

    update public.inventory_reservations set status = 'dispatched' where id = v_res.res_id;

    insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id, request_id, assignment_id)
    values (v_res.lot_id, 'ready_to_ship', 'dispatched', v_res.qty, 'delivered to requester', v_uid, v_req_id, p_id);
  end loop;

  update public.request_items set confirmed_qty = approved_qty where request_id = v_req_id and approved_qty is not null;
  update public.assignments set state = 'delivered', completed_at = now() where id = p_id;
  update public.requests set status = 'fulfilled', fulfilled_at = now(), updated_at = now() where id = v_req_id;

  insert into public.assignment_events (assignment_id, event_type, actor_id, payload) values
    (p_id, 'otp_verified', v_uid, jsonb_build_object('purpose', 'delivery')),
    (p_id, 'delivered', v_uid, null);

  perform public.append_audit_log(
    'delivery_completed', v_uid, 'assignment', p_id, jsonb_build_object('request_id', v_req_id)
  );

  return jsonb_build_object('ok', true, 'state', 'delivered', 'request_status', 'fulfilled');
end;
$$;
-- 3. get_tracking: adds hub_received_at (set once the hub count is done) so the donor's screen can say
-- "delivered to hub". Everything else is unchanged.
create or replace function public.get_tracking(p_ref text, p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := public._request_id_by_token(p_ref, p_token);
  v_r   public.requests%rowtype;
  v_otp text;
begin
  select * into v_r from public.requests where id = v_id;

  if public._active_otp_assignment(v_id, 'delivery') is not null then
    v_otp := 'delivery';
  elsif public._active_otp_assignment(v_id, 'pickup') is not null then
    v_otp := 'pickup';
  end if;

  return jsonb_build_object(
    'public_ref', v_r.public_ref,
    'kind', v_r.kind,
    'status', v_r.status,
    'urgency', v_r.urgency,
    'decline_reason', v_r.decline_reason,
    'created_at', v_r.created_at,
    'approved_at', v_r.approved_at,
    'picked_up_at', v_r.picked_up_at,
    'fulfilled_at', v_r.fulfilled_at,
    'hub_received_at', (
      select max(e.created_at) from public.assignment_events e
        join public.assignments a on a.id = e.assignment_id
       where a.request_id = v_id and e.event_type = 'hub_received'
    ),
    'otp_purpose', v_otp,
    'can_update_pickup_qty', (
      v_r.kind = 'donation_offer' and v_r.picked_up_at is null
      and v_r.status in ('approved', 'awaiting_assignment', 'assigned', 'in_progress')
    ),
    'incident_status', (
      select i.status from public.incidents i where i.request_id = v_id order by i.created_at desc limit 1
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'item_type', i.item_type, 'unit', i.unit,
        'requested_qty', i.requested_qty, 'approved_qty', i.approved_qty,
        'donor_qty', i.donor_qty, 'confirmed_qty', i.confirmed_qty
      ) order by i.item_type, i.id), '[]'::jsonb)
      from public.request_items i where i.request_id = v_id
    ),
    'assignments', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'assignment_type', a.assignment_type,
        'state', a.state,
        'volunteer_first_name', split_part(p.full_name, ' ', 1),
        'accepted_at', a.accepted_at,
        'completed_at', a.completed_at,
        'location', case
          when a.state in ('en_route_to_pickup', 'en_route_to_destination') and l.assignment_id is not null
            then jsonb_build_object('lat', l.lat, 'lng', l.lng, 'updated_at', l.updated_at)
        end
      ) order by a.created_at), '[]'::jsonb)
      from public.assignments a
      left join public.profiles p on p.id = a.volunteer_id
      left join public.volunteer_locations l on l.assignment_id = a.id
      where a.request_id = v_id and a.state not in ('declined', 'expired', 'cancelled')
    )
  );
end;
$$;
-- 4. admin_receive_donation: the hub count.
-- p_items: [{ "item_id": uuid, "qty": n }] with n a whole number of kits >= 0 (counted at the hub). Every item the
-- driver confirmed (confirmed_qty > 0) must be listed. Works once per pickup job, and only while the job is
-- picked_up or en_route_to_destination (picked up, not finished).
-- Creates one lot per counted item in phase 'received' and a movement for each; the reserve check runs by itself
-- through the inventory_lots trigger. If any counted quantity differs from the driver's confirmed one, a
-- hub_shortfall incident is opened for the assignment and the driver. The incident does not stop the job.
create or replace function public.admin_receive_donation(p_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := auth.uid();
  v_a       public.assignments%rowtype;
  v_req     public.requests%rowtype;
  v_req_id  uuid;
  v_el      jsonb;
  v_qty     numeric;
  v_row     record;
  v_lot_id  uuid;
  v_lots    int := 0;
  v_exp_tot numeric := 0;
  v_cnt_tot numeric := 0;
  v_rows    jsonb := '[]'::jsonb;
  v_diff    jsonb := '[]'::jsonb;
  v_inc     uuid;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_req from public.requests where id = v_req_id for update;
  select * into v_a from public.assignments where id = p_id for update;

  if v_a.assignment_type <> 'pickup'
     or v_a.state not in ('picked_up', 'en_route_to_destination')
     or v_req.status not in ('assigned', 'in_progress') then
    raise exception 'invalid_state';
  end if;
  if public._hub_counted(p_id) then raise exception 'already_received'; end if;

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'invalid_items';
  end if;
  for v_el in select e from jsonb_array_elements(p_items) e loop
    if jsonb_typeof(v_el) <> 'object'
       or jsonb_typeof(v_el->'item_id') is distinct from 'string'
       or jsonb_typeof(v_el->'qty') is distinct from 'number' then
      raise exception 'invalid_items';
    end if;
    v_qty := (v_el->>'qty')::numeric;
    if v_qty < 0 or v_qty > 1000000 or v_qty <> trunc(v_qty) then raise exception 'invalid_quantity'; end if;
    if not exists (select 1 from public.request_items i
                    where i.request_id = v_req_id and i.id::text = v_el->>'item_id') then
      raise exception 'invalid_items';
    end if;
  end loop;
  if (select count(distinct e->>'item_id') from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
    raise exception 'invalid_items';
  end if;
  if exists (
    select 1 from public.request_items i
     where i.request_id = v_req_id and coalesce(i.confirmed_qty, 0) > 0
       and not exists (select 1 from jsonb_array_elements(p_items) e where e->>'item_id' = i.id::text)
  ) then raise exception 'invalid_items'; end if;

  for v_row in
    select i.id, i.item_type, i.unit,
           coalesce(i.confirmed_qty, 0) as expected,
           coalesce((select (e->>'qty')::numeric from jsonb_array_elements(p_items) e
                      where e->>'item_id' = i.id::text), 0) as counted
      from public.request_items i
     where i.request_id = v_req_id
     order by i.item_type, i.id
  loop
    v_exp_tot := v_exp_tot + v_row.expected;
    v_cnt_tot := v_cnt_tot + v_row.counted;

    if v_row.counted > 0 then
      insert into public.inventory_lots (item_type, unit, quantity, phase, provider_name, provider_contact, source_request_id, created_by)
      values (v_row.item_type, v_row.unit, v_row.counted, 'received',
              v_req.requester_name, v_req.requester_phone, v_req_id, v_admin)
      returning id into v_lot_id;

      insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id, request_id, assignment_id)
      values (v_lot_id, null, 'received', v_row.counted, 'hub receipt', v_admin, v_req_id, p_id);

      v_lots := v_lots + 1;
    end if;

    v_rows := v_rows || jsonb_build_object(
      'item_id', v_row.id, 'item_type', v_row.item_type, 'unit', v_row.unit,
      'expected_qty', v_row.expected, 'counted_qty', v_row.counted);
    if v_row.expected <> v_row.counted then
      v_diff := v_diff || jsonb_build_object(
        'item_id', v_row.id, 'item_type', v_row.item_type, 'unit', v_row.unit,
        'expected_qty', v_row.expected, 'counted_qty', v_row.counted);
    end if;
  end loop;

  if jsonb_array_length(v_diff) > 0 then
    insert into public.incidents (assignment_id, request_id, incident_type, reporter_note, reported_shortfall, reported_by_volunteer_id)
    values (p_id, v_req_id, 'hub_shortfall',
            format('Hub count differs from the driver''s pickup: expected %s kits, counted %s.', v_exp_tot, v_cnt_tot),
            v_diff, v_a.volunteer_id)
    returning id into v_inc;

    insert into public.assignment_events (assignment_id, event_type, actor_id, payload)
    values (p_id, 'incident_opened', v_admin,
            jsonb_build_object('type', 'hub_shortfall', 'incident_id', v_inc));

    perform public.append_audit_log(
      'incident_opened', v_admin, 'incident', v_inc,
      jsonb_build_object('request_id', v_req_id, 'assignment_id', p_id, 'type', 'hub_shortfall')
    );
  end if;

  insert into public.assignment_events (assignment_id, event_type, actor_id, payload)
  values (p_id, 'hub_received', v_admin,
          jsonb_build_object('items', v_rows, 'expected_total', v_exp_tot, 'counted_total', v_cnt_tot,
                             'incident_id', v_inc));

  perform public.append_audit_log(
    'hub_received', v_admin, 'assignment', p_id,
    jsonb_build_object('request_id', v_req_id, 'expected_total', v_exp_tot, 'counted_total', v_cnt_tot,
                       'shortfall', v_inc is not null)
  );

  return jsonb_build_object(
    'assignment_id', p_id,
    'lots_created', v_lots,
    'items', v_rows,
    'shortfall', v_inc is not null,
    'incident_id', v_inc
  );
end;
$$;

-- 5. Privileges (see 20261122000011_function_privileges.sql: service_role only unless it is a client RPC) ------
revoke all on function public.admin_receive_donation(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_receive_donation(uuid, jsonb) to authenticated;
revoke all on function public.driver_verify_otp(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.driver_verify_otp(uuid, text, text, boolean) to authenticated;
revoke all on function public.get_tracking(text, text) from public, anon, authenticated;
grant execute on function public.get_tracking(text, text) to anon, authenticated;