-- Part 3: delivery progress, OTP and requester tracking.
-- Lock order everywhere: request row, then assignment row, then OTP row, then inventory lots.
--
-- driver_verify_otp returns { ok: false, reason } for OTP problems instead of raising, because a raised
-- error would roll back the attempt counter. reasons: invalid_otp | otp_locked | otp_expired | otp_used |
-- otp_not_issued | quantity_changed.
-- Raised errors: unauthorized | forbidden | not_found | invalid_purpose | invalid_state | invalid_transition |
--   otp_required | otp_not_available | too_many_requests | invalid_items | invalid_note | already_reported |
--   nothing_to_pick_up

create or replace function public._request_id_by_token(p_ref text, p_token text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  select r.id into v_id
    from public.requests r
   where r.public_ref = upper(btrim(coalesce(p_ref, '')))
     and r.tracking_token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if v_id is null then raise exception 'not_found'; end if;
  return v_id;
end;
$$;

-- The assignment whose OTP may be shown or checked right now, or null.
create or replace function public._active_otp_assignment(p_req uuid, p_purpose text)
returns uuid
language sql
stable
security definer
set search_path = public, extensions
as $$
  select a.id
    from public.assignments a
   where a.request_id = p_req
     and a.volunteer_id is not null
     and ((p_purpose = 'delivery' and a.assignment_type = 'delivery'
           and a.state in ('picked_up', 'en_route_to_destination'))
       or (p_purpose = 'pickup' and a.assignment_type = 'pickup'
           and a.state in ('accepted', 'en_route_to_pickup')))
   order by a.created_at desc
   limit 1;
$$;

revoke all on function public._request_id_by_token(text, text) from public, anon, authenticated;
revoke all on function public._active_otp_assignment(uuid, text) from public, anon, authenticated;

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

-- Only a hash of the code is stored, so a code cannot be read back: every call issues a fresh one and
-- invalidates the previous live code. Max 10 codes per assignment and purpose per hour.
create or replace function public.requester_get_otp(p_ref text, p_token text, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := public._request_id_by_token(p_ref, p_token);
  v_a_id    uuid;
  v_code    text;
  v_expires timestamptz := now() + interval '15 minutes';
begin
  if p_purpose is null or p_purpose not in ('pickup', 'delivery') then raise exception 'invalid_purpose'; end if;

  perform 1 from public.requests where id = v_id for update;

  v_a_id := public._active_otp_assignment(v_id, p_purpose);
  if v_a_id is null then raise exception 'otp_not_available'; end if;

  if (select count(*) from public.otp_challenges
       where assignment_id = v_a_id and purpose = p_purpose and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_requests';
  end if;

  update public.otp_challenges
     set expires_at = now()
   where assignment_id = v_a_id and purpose = p_purpose and consumed_at is null and expires_at > now();

  v_code := lpad((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');

  insert into public.otp_challenges (assignment_id, purpose, code_hash, expires_at)
  values (v_a_id, p_purpose, crypt(v_code, gen_salt('bf')), v_expires);

  perform public.append_audit_log(
    'otp_issued', null, 'assignment', v_a_id,
    jsonb_build_object('purpose', p_purpose, 'request_id', v_id)
  );

  return jsonb_build_object('code', v_code, 'purpose', p_purpose, 'expires_at', v_expires);
end;
$$;

-- Donor lowers quantities before pickup. Only a reduction is allowed (never above the approved quantity),
-- and at least one item must stay above zero. p_items: [{ "item_id": uuid, "qty": number }].
create or replace function public.requester_update_pickup_qty(p_ref text, p_token text, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := public._request_id_by_token(p_ref, p_token);
  v_req public.requests%rowtype;
begin
  select * into v_req from public.requests where id = v_id for update;
  if v_req.kind <> 'donation_offer'
     or v_req.picked_up_at is not null
     or v_req.status not in ('approved', 'awaiting_assignment', 'assigned', 'in_progress') then
    raise exception 'invalid_state';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'invalid_items';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
     where jsonb_typeof(e->'qty') is distinct from 'number'
        or not exists (select 1 from public.request_items i
                        where i.request_id = v_id and i.id::text = e->>'item_id'
                          and (e->>'qty')::numeric between 0 and coalesce(i.approved_qty, i.requested_qty))
  ) then raise exception 'invalid_items'; end if;
  if (select count(distinct e->>'item_id') from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
    raise exception 'invalid_items';
  end if;

  update public.request_items i
     set donor_qty = (e->>'qty')::numeric
    from jsonb_array_elements(p_items) e
   where i.request_id = v_id and i.id::text = e->>'item_id';

  if (select coalesce(sum(coalesce(donor_qty, approved_qty, requested_qty)), 0)
        from public.request_items where request_id = v_id) <= 0 then
    raise exception 'invalid_items';
  end if;

  insert into public.assignment_events (assignment_id, event_type, payload)
  select a.id, 'pickup_qty_changed', p_items
    from public.assignments a
   where a.request_id = v_id and a.assignment_type = 'pickup' and a.state not in ('declined', 'expired', 'cancelled');

  perform public.append_audit_log('donor_qty_changed', null, 'request', v_id, jsonb_build_object('public_ref', v_req.public_ref));

  return jsonb_build_object('items', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', i.id, 'item_type', i.item_type, 'unit', i.unit,
      'approved_qty', coalesce(i.approved_qty, i.requested_qty),
      'qty', coalesce(i.donor_qty, i.approved_qty, i.requested_qty)
    ) order by i.item_type, i.id), '[]'::jsonb)
    from public.request_items i where i.request_id = v_id
  ));
end;
$$;

-- Requester's report after the driver completed the delivery OTP. p_full = true confirms everything arrived;
-- false opens a short_delivery incident, sets the assignment to disputed and the request to partially_fulfilled.
-- p_shortfall (optional): [{ "item_id": uuid, "received_qty": number }].
create or replace function public.requester_confirm_delivery(
  p_ref text, p_token text, p_full boolean, p_note text default null, p_shortfall jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := public._request_id_by_token(p_ref, p_token);
  v_req    public.requests%rowtype;
  v_a      public.assignments%rowtype;
  v_note   text := btrim(coalesce(p_note, ''));
  v_short  jsonb := null;
  v_inc    uuid;
begin
  if p_full is null then raise exception 'invalid_items'; end if;

  select * into v_req from public.requests where id = v_id for update;
  if v_req.kind <> 'resource_request' then raise exception 'invalid_state'; end if;

  select * into v_a from public.assignments
   where request_id = v_id and assignment_type = 'delivery' and state in ('delivered', 'disputed')
   order by created_at desc limit 1 for update;
  if not found then raise exception 'invalid_state'; end if;

  if p_full then
    if v_a.state = 'disputed' then raise exception 'already_reported'; end if;
    if not exists (select 1 from public.assignment_events where assignment_id = v_a.id and event_type = 'delivery_confirmed') then
      insert into public.assignment_events (assignment_id, event_type, payload)
      values (v_a.id, 'delivery_confirmed', jsonb_build_object('requester_full', true));
    end if;
    return jsonb_build_object('request_status', v_req.status, 'confirmed', true);
  end if;

  if v_a.state = 'disputed'
     or exists (select 1 from public.incidents where assignment_id = v_a.id and status in ('open', 'under_review')) then
    raise exception 'already_reported';
  end if;
  if char_length(v_note) not between 2 and 500 then raise exception 'invalid_note'; end if;

  if p_shortfall is not null then
    if jsonb_typeof(p_shortfall) <> 'array' or jsonb_array_length(p_shortfall) = 0 then raise exception 'invalid_items'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_shortfall) e
       where jsonb_typeof(e->'received_qty') is distinct from 'number'
          or not exists (select 1 from public.request_items i
                          where i.request_id = v_id and i.id::text = e->>'item_id'
                            and (e->>'received_qty')::numeric between 0 and coalesce(i.approved_qty, i.requested_qty))
    ) then raise exception 'invalid_items'; end if;
    if (select count(distinct e->>'item_id') from jsonb_array_elements(p_shortfall) e) <> jsonb_array_length(p_shortfall) then
      raise exception 'invalid_items';
    end if;

    select jsonb_agg(jsonb_build_object(
             'item_id', i.id, 'item_type', i.item_type,
             'approved_qty', coalesce(i.approved_qty, i.requested_qty),
             'received_qty', (e->>'received_qty')::numeric))
      into v_short
      from jsonb_array_elements(p_shortfall) e
      join public.request_items i on i.id::text = e->>'item_id' and i.request_id = v_id;

    update public.request_items i
       set confirmed_qty = (e->>'received_qty')::numeric
      from jsonb_array_elements(p_shortfall) e
     where i.request_id = v_id and i.id::text = e->>'item_id';
  end if;

  insert into public.incidents (assignment_id, request_id, incident_type, reporter_note, reported_shortfall)
  values (v_a.id, v_id, 'short_delivery', v_note, v_short)
  returning id into v_inc;

  update public.assignments set state = 'disputed' where id = v_a.id;
  update public.requests set status = 'partially_fulfilled', updated_at = now() where id = v_id;

  insert into public.assignment_events (assignment_id, event_type, payload)
  values (v_a.id, 'incident_opened', jsonb_build_object('type', 'short_delivery', 'incident_id', v_inc));

  perform public.append_audit_log(
    'incident_opened', null, 'incident', v_inc,
    jsonb_build_object('request_id', v_id, 'assignment_id', v_a.id, 'type', 'short_delivery')
  );

  return jsonb_build_object('incident_id', v_inc, 'request_status', 'partially_fulfilled', 'confirmed', false);
end;
$$;

-- Forward-only moves the driver or volunteer may make. The OTP steps are not here on purpose:
-- delivery -> delivered and pickup -> picked_up only happen through driver_verify_otp (error otp_required).
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
      ('delivery',   'en_route_to_pickup',      'picked_up'),
      ('delivery',   'picked_up',               'en_route_to_destination'),
      ('pickup',     'accepted',                'en_route_to_pickup'),
      ('pickup',     'picked_up',               'en_route_to_destination'),
      ('pickup',     'en_route_to_destination', 'delivered'),
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
    if (v_a.assignment_type = 'delivery' and p_state = 'delivered')
       or (v_a.assignment_type = 'pickup' and p_state = 'picked_up') then
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
  v_item    record;
  v_res     record;
  v_lot_id  uuid;
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

    for v_item in
      select i.item_type, i.unit, i.confirmed_qty
        from public.request_items i
       where i.request_id = v_req_id and i.confirmed_qty > 0
       order by i.item_type, i.id
    loop
      insert into public.inventory_lots (item_type, unit, quantity, phase, provider_name, provider_contact, source_request_id, created_by)
      values (v_item.item_type, v_item.unit, v_item.confirmed_qty, 'received',
              v_req.requester_name, v_req.requester_phone, v_req_id, v_uid)
      returning id into v_lot_id;

      insert into public.inventory_movements (lot_id, from_phase, to_phase, quantity, reason, actor_id, request_id, assignment_id)
      values (v_lot_id, null, 'received', v_item.confirmed_qty, 'donation pickup', v_uid, v_req_id, p_id);

      v_total := v_total + v_item.confirmed_qty;
    end loop;
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

revoke all on function public.get_tracking(text, text) from public, anon, authenticated;
revoke all on function public.requester_get_otp(text, text, text) from public, anon, authenticated;
revoke all on function public.requester_update_pickup_qty(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.requester_confirm_delivery(text, text, boolean, text, jsonb) from public, anon, authenticated;
revoke all on function public.update_assignment_state(uuid, text) from public, anon, authenticated;
revoke all on function public.driver_verify_otp(uuid, text, text, boolean) from public, anon, authenticated;

grant execute on function public.get_tracking(text, text) to anon, authenticated;
grant execute on function public.requester_get_otp(text, text, text) to anon, authenticated;
grant execute on function public.requester_update_pickup_qty(text, text, jsonb) to anon, authenticated;
grant execute on function public.requester_confirm_delivery(text, text, boolean, text, jsonb) to anon, authenticated;
grant execute on function public.update_assignment_state(uuid, text) to authenticated;
grant execute on function public.driver_verify_otp(uuid, text, text, boolean) to authenticated;