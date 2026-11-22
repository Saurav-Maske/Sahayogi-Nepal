-- Resource-request flow at the hub (D4, D5).
--
-- D4: the driver can only take the reserved items from the hub with the admin's code. admin_issue_otp now
--     issues a hub_pickup code for a delivery job that is accepted or en_route_to_pickup. The driver enters it in
--     driver_verify_otp (purpose hub_pickup) and only then the job is picked_up. update_assignment_state no longer
--     allows delivery -> picked_up (otp_required). Stock stays reserved until the requester's delivery code.
--     admin_issue_otp picks the purpose from the job: pickup job after the count = hub_dropoff, delivery job
--     before pickup = hub_pickup. Same code rules as before (6 digits, hashed, 15 minutes, 5 attempts, 10 per hour).
-- D5: driver_report_issue also works for a delivery job before hub_pickup. The incident type is hub_pickup_refused
--     or hub_items_mismatch. The job is released to offers (that driver excluded) and the request goes back to
--     awaiting_assignment. DECISION (c): the reserved stock is KEPT, because the request still has to be delivered
--     by another driver; the admin can decline the request from the incident if it should not be. Say if you want
--     the reservation released instead.
-- Safe to run more than once.

do $$
declare c record;
begin
  for c in
    select con.conname from pg_constraint con
     where con.conrelid = 'public.otp_challenges'::regclass and con.contype = 'c'
       and pg_get_constraintdef(con.oid) like '%purpose%'
  loop
    execute format('alter table public.otp_challenges drop constraint %I', c.conname);
  end loop;
end
$$;

alter table public.otp_challenges
  drop constraint if exists otp_challenges_purpose_check,
  add constraint otp_challenges_purpose_check
    check (purpose in ('pickup', 'delivery', 'hub_dropoff', 'hub_pickup'));

-- 2. admin_issue_otp: the admin gets the code once (only a hash is stored) and reads it to the driver.
create or replace function public.admin_issue_otp(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := auth.uid();
  v_a       public.assignments%rowtype;
  v_req_id  uuid;
  v_code    text;
  v_purpose text;
  v_req_status public.request_status;
  v_expires timestamptz := now() + interval '15 minutes';
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select status into v_req_status from public.requests where id = v_req_id for update;
  select * into v_a from public.assignments where id = p_id for update;

  if v_a.volunteer_id is null or v_req_status not in ('assigned', 'in_progress') then raise exception 'invalid_state'; end if;
  if v_a.assignment_type = 'pickup' and v_a.state in ('picked_up', 'en_route_to_destination') then
    -- donation: the code that finishes the job, only after the hub count
    if not public._hub_counted(p_id) then raise exception 'not_received'; end if;
    v_purpose := 'hub_dropoff';
  elsif v_a.assignment_type = 'delivery' and v_a.state in ('accepted', 'en_route_to_pickup') then
    -- resource request: the code the driver enters to take the reserved items from the hub
    v_purpose := 'hub_pickup';
  else
    raise exception 'invalid_state';
  end if;

  if (select count(*) from public.otp_challenges
       where assignment_id = p_id and purpose = v_purpose and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_requests';
  end if;

  update public.otp_challenges
     set expires_at = now()
   where assignment_id = p_id and purpose = v_purpose and consumed_at is null and expires_at > now();

  v_code := lpad((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');

  insert into public.otp_challenges (assignment_id, purpose, code_hash, expires_at)
  values (p_id, v_purpose, crypt(v_code, gen_salt('bf')), v_expires);

  perform public.append_audit_log(
    'otp_issued', v_admin, 'assignment', p_id,
    jsonb_build_object('purpose', v_purpose, 'request_id', v_req_id)
  );

  return jsonb_build_object('code', v_code, 'purpose', v_purpose, 'expires_at', v_expires, 'assignment_id', p_id);
end;
$$;

-- driver_verify_otp with the hub_pickup and hub_dropoff purposes.
-- purposes: pickup (donor's code), delivery (requester's code), hub_dropoff (the admin's code, pickup jobs only),
-- hub_pickup (the admin's code, delivery jobs only: the driver takes the reserved items from the hub).
-- hub_pickup moves a delivery job to picked_up; stock stays reserved until the requester's delivery code.
-- Pickup records what the driver confirmed and puts the job in transit; stock is created at the hub count.
-- hub_dropoff finishes the pickup job: delivered, and the donation request fulfilled.
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
  v_type    text;
  v_open    int;
  v_items   jsonb;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;
  if p_purpose is null or p_purpose not in ('pickup', 'delivery', 'hub_dropoff', 'hub_pickup') then raise exception 'invalid_purpose'; end if;
  v_type := case p_purpose when 'hub_dropoff' then 'pickup' when 'hub_pickup' then 'delivery' else p_purpose end;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_req from public.requests where id = v_req_id for update;
  select * into v_a from public.assignments where id = p_id for update;
  if v_a.volunteer_id is distinct from v_uid then raise exception 'not_found'; end if;
  if v_a.assignment_type::text <> v_type then raise exception 'invalid_purpose'; end if;

  if v_req.status not in ('assigned', 'in_progress')
     or (p_purpose in ('pickup', 'hub_pickup') and v_a.state not in ('accepted', 'en_route_to_pickup'))
     or (p_purpose in ('delivery', 'hub_dropoff') and v_a.state not in ('picked_up', 'en_route_to_destination'))
     or (p_purpose = 'hub_dropoff' and not public._hub_counted(p_id)) then
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

  if p_purpose = 'hub_pickup' then
    update public.otp_challenges set consumed_at = now() where id = v_ch.id;

    update public.assignments set state = 'picked_up' where id = p_id;
    if v_req.status = 'assigned' and (select count(*) from public.assignments where request_id = v_req_id) = 1 then
      update public.requests set status = 'in_progress', updated_at = now() where id = v_req_id;
    end if;

    insert into public.assignment_events (assignment_id, event_type, actor_id, payload) values
      (p_id, 'otp_verified', v_uid, jsonb_build_object('purpose', 'hub_pickup')),
      (p_id, 'picked_up', v_uid, jsonb_build_object('from', 'hub'));

    perform public.append_audit_log(
      'hub_pickup_confirmed', v_uid, 'assignment', p_id, jsonb_build_object('request_id', v_req_id)
    );

    return jsonb_build_object('ok', true, 'state', 'picked_up',
                              'request_status', (select status from public.requests where id = v_req_id));
  end if;

  if p_purpose = 'hub_dropoff' then
    update public.otp_challenges set consumed_at = now() where id = v_ch.id;

    update public.assignments set state = 'delivered', completed_at = now() where id = p_id;

    select count(*) into v_open from public.assignments
     where request_id = v_req_id and id <> p_id
       and state not in ('delivered', 'declined', 'expired', 'cancelled');
    if v_open = 0 then
      update public.requests set status = 'fulfilled', fulfilled_at = now(), updated_at = now() where id = v_req_id;
    end if;

    insert into public.assignment_events (assignment_id, event_type, actor_id, payload) values
      (p_id, 'otp_verified', v_uid, jsonb_build_object('purpose', 'hub_dropoff')),
      (p_id, 'delivered', v_uid, jsonb_build_object('to', 'hub'));

    perform public.append_audit_log(
      'hub_dropoff_completed', v_uid, 'assignment', p_id, jsonb_build_object('request_id', v_req_id)
    );

    return jsonb_build_object('ok', true, 'state', 'delivered',
                              'request_status', (select status from public.requests where id = v_req_id));
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

-- 4. update_assignment_state: a pickup job can no longer be marked delivered by the driver.
-- Forward-only moves the driver or volunteer may make. The OTP steps are not here on purpose:
-- delivery -> picked_up (the hub_pickup code), delivery -> delivered, pickup -> picked_up and pickup -> delivered
-- (the hub_dropoff code) only happen through driver_verify_otp (error otp_required).
-- Multi-slot requests stay 'assigned' until every slot is delivered; only single-assignment requests
-- switch to in_progress, so a released slot can never be hidden from my_offers.
create or replace function public.update_assignment_state(p_id uuid, p_state text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_p      public.profiles%rowtype;
  v_a      public.assignments%rowtype;
  v_req    public.requests%rowtype;
  v_req_id uuid;
  v_open   int;
  v_status request_status;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_req from public.requests where id = v_req_id for update;
  select * into v_a from public.assignments where id = p_id for update;
  if v_a.volunteer_id is distinct from v_uid then raise exception 'not_found'; end if;
  if v_req.status not in ('awaiting_assignment', 'assigned', 'in_progress') then raise exception 'invalid_state'; end if;

  if not exists (
    select 1 from (values
      ('delivery',   'accepted',                'en_route_to_pickup'),
      ('delivery',   'picked_up',               'en_route_to_destination'),
      ('pickup',     'accepted',                'en_route_to_pickup'),
      ('pickup',     'picked_up',               'en_route_to_destination'),
      ('manpower',   'accepted',                'en_route_to_destination'),
      ('manpower',   'accepted',                'delivered'),
      ('manpower',   'en_route_to_destination', 'delivered'),
      ('healthcare', 'accepted',                'en_route_to_destination'),
      ('healthcare', 'accepted',                'delivered'),
      ('healthcare', 'en_route_to_destination', 'delivered'),
      ('transport',  'accepted',                'en_route_to_destination'),
      ('transport',  'accepted',                'delivered'),
      ('transport',  'en_route_to_destination', 'delivered')
    ) t(tp, f, s)
    where t.tp = v_a.assignment_type::text and t.f = v_a.state::text and t.s = p_state
  ) then
    if (v_a.assignment_type = 'delivery' and p_state in ('picked_up', 'delivered'))
       or (v_a.assignment_type = 'pickup' and p_state in ('picked_up', 'delivered')) then
      raise exception 'otp_required';
    end if;
    raise exception 'invalid_transition';
  end if;

  update public.assignments
     set state = p_state::assignment_state,
         completed_at = case when p_state = 'delivered' then now() else completed_at end
   where id = p_id;

  insert into public.assignment_events (assignment_id, event_type, actor_id)
  values (p_id, p_state, v_uid);

  if v_req.status = 'assigned' and (select count(*) from public.assignments where request_id = v_req_id) = 1 then
    update public.requests set status = 'in_progress', updated_at = now() where id = v_req_id;
  end if;

  if p_state = 'delivered' then
    select count(*) into v_open from public.assignments
     where request_id = v_req_id and state not in ('delivered', 'declined', 'expired', 'cancelled');
    if v_open = 0 then
      update public.requests set status = 'fulfilled', fulfilled_at = now(), updated_at = now() where id = v_req_id;
    end if;
  end if;

  perform public.append_audit_log(
    'assignment_state_changed', v_uid, 'assignment', p_id,
    jsonb_build_object('request_id', v_req_id, 'from', v_a.state, 'to', p_state)
  );

  select status into v_status from public.requests where id = v_req_id;
  return jsonb_build_object('id', p_id, 'state', p_state, 'request_status', v_status);
end;
$$;

create or replace function public.driver_report_issue(p_id uuid, p_type text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_a      public.assignments%rowtype;
  v_req_id uuid;
  v_type   text := btrim(coalesce(p_type, ''));
  v_note   text := btrim(coalesce(p_note, ''));
  v_inc    uuid;
  v_inc_type text;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform 1 from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  if v_type not in ('pickup_refused', 'items_mismatch') then raise exception 'invalid_type'; end if;
  if char_length(v_note) not between 2 and 500 then raise exception 'invalid_note'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform 1 from public.requests where id = v_req_id for update;

  select * into v_a from public.assignments where id = p_id for update;
  if v_a.volunteer_id is distinct from v_uid then raise exception 'not_found'; end if;
  -- donation pickup (before the donor's code) or resource delivery (before the hub_pickup code)
  if v_a.assignment_type not in ('pickup', 'delivery') or v_a.state not in ('accepted', 'en_route_to_pickup') then
    raise exception 'invalid_state';
  end if;
  v_inc_type := case when v_a.assignment_type = 'delivery' then 'hub_' || v_type else v_type end;

  insert into public.incidents (assignment_id, request_id, incident_type, reporter_note, reported_by_volunteer_id)
  values (p_id, v_req_id, v_inc_type, v_note, v_uid)
  returning id into v_inc;

  update public.assignments
     set volunteer_id = null, state = 'offered', accepted_at = null,
         declined_by = array_append(declined_by, v_uid)
   where id = p_id;
  update public.requests
     set status = 'awaiting_assignment', updated_at = now()
   where id = v_req_id and status in ('assigned', 'in_progress');
  delete from public.volunteer_locations where assignment_id = p_id;

  insert into public.assignment_events (assignment_id, event_type, actor_id, payload)
  values (p_id, 'incident_opened', v_uid, jsonb_build_object('type', v_inc_type, 'incident_id', v_inc, 'released', true));

  perform public.append_audit_log(
    'incident_opened', v_uid, 'incident', v_inc,
    jsonb_build_object('request_id', v_req_id, 'assignment_id', p_id, 'type', v_inc_type)
  );

  return jsonb_build_object('incident_id', v_inc, 'released', true);
end;
$$;

revoke all on function public.admin_issue_otp(uuid) from public, anon, authenticated;
grant execute on function public.admin_issue_otp(uuid) to authenticated;
revoke all on function public.driver_verify_otp(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.driver_verify_otp(uuid, text, text, boolean) to authenticated;
revoke all on function public.update_assignment_state(uuid, text) from public, anon, authenticated;
grant execute on function public.update_assignment_state(uuid, text) to authenticated;
revoke all on function public.driver_report_issue(uuid, text, text) from public, anon, authenticated;
grant execute on function public.driver_report_issue(uuid, text, text) to authenticated;