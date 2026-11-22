-- Part 2: assignments and offers.
-- Errors: forbidden | unauthorized | not_found | invalid_state | already_assigned | hub_not_configured
--   invalid_volunteers_needed | nothing_to_deliver
--   claim_assignment: already_claimed | not_eligible | already_on_request | not_available | not_found

-- Who may take an open assignment. Tier A is shown to volunteers with exactly {A} until escalate_at,
-- then to everyone who holds A. Tier B needs B, tier C needs C.
create or replace function public._tier_open_to(p_tier text, p_categories text[], p_escalate_at timestamptz)
returns boolean
language sql
stable
as $$
  select case p_tier
    when 'A' then
      case
        when p_escalate_at is not null and now() < p_escalate_at
          then p_categories @> array['A']::text[] and p_categories <@ array['A']::text[]
        else p_categories @> array['A']::text[]
      end
    when 'B' then p_categories @> array['B']::text[]
    when 'C' then p_categories @> array['C']::text[]
    else false
  end;
$$;

revoke all on function public._tier_open_to(text, text[], timestamptz) from public, anon, authenticated;

create or replace function public.create_assignments(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := auth.uid();
  v_req    public.requests%rowtype;
  v_hub    jsonb;
  v_lat    double precision;
  v_lng    double precision;
  v_hub_pt jsonb;
  v_pt     jsonb;
  v_type   assignment_type;
  v_tier   text;
  v_n      int := 1;
  v_esc    timestamptz := null;
  v_route  jsonb;
  v_items  jsonb := '[]'::jsonb;
  v_ids    jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select * into v_req from public.requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_req.status <> 'approved' then raise exception 'invalid_state'; end if;
  if exists (select 1 from public.assignments where request_id = p_id) then raise exception 'already_assigned'; end if;

  v_lat := st_y(v_req.location::geometry);
  v_lng := st_x(v_req.location::geometry);

  if v_req.kind in ('resource_request', 'donation_offer') then
    select value into v_hub from public.app_settings where key = 'central_inventory';
    if v_hub is null
       or jsonb_typeof(v_hub->'lat') is distinct from 'number'
       or jsonb_typeof(v_hub->'lng') is distinct from 'number' then
      raise exception 'hub_not_configured';
    end if;
    v_hub_pt := jsonb_build_object(
      'label', 'central inventory',
      'lat', (v_hub->>'lat')::double precision,
      'lng', (v_hub->>'lng')::double precision
    );
  end if;

  if v_req.kind = 'resource_request' then
    v_type := 'delivery';
    v_tier := 'B';
    v_pt := jsonb_build_object('label', 'requester', 'lat', v_lat, 'lng', v_lng);
    v_route := jsonb_build_array(v_hub_pt, v_pt);
    select coalesce(jsonb_agg(jsonb_build_object('item_type', i.item_type, 'qty', i.approved_qty, 'unit', i.unit)
                              order by i.item_type), '[]'::jsonb)
      into v_items
      from public.request_items i
     where i.request_id = p_id and coalesce(i.approved_qty, 0) > 0;
    if jsonb_array_length(v_items) = 0 then raise exception 'nothing_to_deliver'; end if;

  elsif v_req.kind = 'donation_offer' then
    v_type := 'pickup';
    v_tier := 'B';
    v_pt := jsonb_build_object('label', 'donor', 'lat', v_lat, 'lng', v_lng);
    v_route := jsonb_build_array(v_pt, v_hub_pt);
    select coalesce(jsonb_agg(jsonb_build_object('item_type', i.item_type, 'qty', coalesce(i.approved_qty, i.requested_qty), 'unit', i.unit)
                              order by i.item_type), '[]'::jsonb)
      into v_items
      from public.request_items i
     where i.request_id = p_id and coalesce(i.approved_qty, i.requested_qty) > 0;
    if jsonb_array_length(v_items) = 0 then raise exception 'nothing_to_deliver'; end if;

  else
    if v_req.volunteers_needed is null or v_req.volunteers_needed < 1 then
      raise exception 'invalid_volunteers_needed';
    end if;
    v_n := v_req.volunteers_needed;
    v_pt := jsonb_build_object('label', 'requester', 'lat', v_lat, 'lng', v_lng);
    v_route := jsonb_build_array(v_pt);
    if v_req.kind = 'manpower_request' then
      v_type := 'manpower';
      v_tier := 'A';
      v_esc := now() + interval '60 seconds';
    elsif v_req.kind = 'healthcare_request' then
      v_type := 'healthcare';
      v_tier := 'C';
    else
      v_type := 'transport';
      v_tier := 'B';
    end if;
  end if;

  with ins as (
    insert into public.assignments (request_id, assignment_type, required_tier, escalate_at, route_snapshot, items_snapshot)
    select p_id, v_type, v_tier, v_esc, v_route, v_items
      from generate_series(1, v_n)
    returning id, assignment_type, required_tier
  )
  select jsonb_agg(jsonb_build_object('id', id, 'assignment_type', assignment_type, 'required_tier', required_tier))
    into v_ids
    from ins;

  insert into public.assignment_events (assignment_id, event_type, actor_id)
  select a.id, 'offered', v_admin from public.assignments a where a.request_id = p_id;

  update public.requests set status = 'awaiting_assignment', updated_at = now() where id = p_id;

  perform public.append_audit_log(
    'assignments_created', v_admin, 'request', p_id,
    jsonb_build_object('kind', v_req.kind, 'public_ref', v_req.public_ref, 'count', v_n)
  );

  return jsonb_build_object('request_id', p_id, 'status', 'awaiting_assignment', 'assignments', v_ids);
end;
$$;

-- Offers show only an approximate location (2 decimals) and no requester contact until the offer is claimed.
create or replace function public.my_offers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_p   public.profiles%rowtype;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  return coalesce((
    select jsonb_agg(o.j order by o.urg, o.offered_at)
    from (
      select
        case r.urgency when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end as urg,
        a.offered_at,
        jsonb_build_object(
          'id', a.id,
          'request_id', r.id,
          'public_ref', r.public_ref,
          'kind', r.kind,
          'assignment_type', a.assignment_type,
          'required_tier', a.required_tier,
          'urgency', r.urgency,
          'offered_at', a.offered_at,
          'escalate_at', a.escalate_at,
          'district', d.name,
          'approx_lat', round(st_y(r.location::geometry)::numeric, 2),
          'approx_lng', round(st_x(r.location::geometry)::numeric, 2),
          'items', a.items_snapshot
        ) as j
      from public.assignments a
      join public.requests r on r.id = a.request_id
      left join public.districts d on d.id = r.district_id
      where a.state = 'offered'
        and a.volunteer_id is null
        and r.status = 'awaiting_assignment'
        and not (v_uid = any (a.declined_by))
        and public._tier_open_to(a.required_tier, v_p.categories, a.escalate_at)
    ) o
  ), '[]'::jsonb);
end;
$$;

-- Own assignment: full detail with requester contact and exact route. Open eligible offer: the redacted view.
create or replace function public.my_assignment_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_p    public.profiles%rowtype;
  v_a    public.assignments%rowtype;
  v_r    public.requests%rowtype;
  v_dist text;
  v_mine boolean;
  v_out  jsonb;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select * into v_a from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_r from public.requests where id = v_a.request_id;

  v_mine := coalesce(v_a.volunteer_id = v_uid, false);
  if not v_mine and not (
       v_a.state = 'offered' and v_a.volunteer_id is null
       and v_r.status = 'awaiting_assignment'
       and not (v_uid = any (v_a.declined_by))
       and public._tier_open_to(v_a.required_tier, v_p.categories, v_a.escalate_at)
  ) then
    raise exception 'not_found';
  end if;

  select name into v_dist from public.districts where id = v_r.district_id;

  v_out := jsonb_build_object(
    'id', v_a.id,
    'request_id', v_r.id,
    'public_ref', v_r.public_ref,
    'kind', v_r.kind,
    'assignment_type', v_a.assignment_type,
    'required_tier', v_a.required_tier,
    'state', v_a.state,
    'urgency', v_r.urgency,
    'district', v_dist,
    'offered_at', v_a.offered_at,
    'escalate_at', v_a.escalate_at,
    'accepted_at', v_a.accepted_at,
    'completed_at', v_a.completed_at,
    'items', v_a.items_snapshot,
    'is_mine', v_mine
  );

  if v_mine then
    v_out := v_out || jsonb_build_object(
      'route', v_a.route_snapshot,
      'requester', jsonb_build_object(
        'name', v_r.requester_name,
        'phone', v_r.requester_phone,
        'lat', st_y(v_r.location::geometry),
        'lng', st_x(v_r.location::geometry),
        'address_note', v_r.address_note,
        'notes', v_r.notes
      )
    );
  else
    v_out := v_out || jsonb_build_object(
      'approx_lat', round(st_y(v_r.location::geometry)::numeric, 2),
      'approx_lng', round(st_x(v_r.location::geometry)::numeric, 2)
    );
  end if;

  return v_out;
end;
$$;

-- The request row is locked first, so claims on one request run one after another. That keeps the
-- "one volunteer per request" rule and the awaiting_assignment -> assigned switch race-free. The claim itself
-- is still a single conditional UPDATE: a second claimer gets zero rows.
create or replace function public.claim_assignment(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_p      public.profiles%rowtype;
  v_a      public.assignments%rowtype;
  v_req_id uuid;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform 1 from public.requests where id = v_req_id for update;

  update public.assignments a
     set volunteer_id = v_uid, state = 'accepted', accepted_at = now()
   where a.id = p_id
     and a.state = 'offered'
     and a.volunteer_id is null
     and not (v_uid = any (a.declined_by))
     and public._tier_open_to(a.required_tier, v_p.categories, a.escalate_at)
     and exists (select 1 from public.requests r where r.id = a.request_id and r.status = 'awaiting_assignment')
     and not exists (
       select 1 from public.assignments b
        where b.request_id = a.request_id and b.volunteer_id = v_uid
          and b.state not in ('declined', 'expired', 'cancelled')
     )
  returning a.* into v_a;

  if not found then
    select * into v_a from public.assignments where id = p_id;
    if v_a.volunteer_id is not null then raise exception 'already_claimed'; end if;
    if v_a.state <> 'offered' then raise exception 'not_available'; end if;
    if v_uid = any (v_a.declined_by)
       or not public._tier_open_to(v_a.required_tier, v_p.categories, v_a.escalate_at) then
      raise exception 'not_eligible';
    end if;
    if exists (
      select 1 from public.assignments b
       where b.request_id = v_a.request_id and b.volunteer_id = v_uid
         and b.state not in ('declined', 'expired', 'cancelled')
    ) then
      raise exception 'already_on_request';
    end if;
    raise exception 'not_available';
  end if;

  insert into public.assignment_events (assignment_id, event_type, actor_id)
  values (v_a.id, 'accepted', v_uid);

  update public.requests
     set status = 'assigned', updated_at = now()
   where id = v_a.request_id
     and status = 'awaiting_assignment'
     and not exists (
       select 1 from public.assignments x
        where x.request_id = v_a.request_id and x.state = 'offered' and x.volunteer_id is null
     );

  perform public.append_audit_log(
    'assignment_claimed', v_uid, 'assignment', v_a.id,
    jsonb_build_object('request_id', v_a.request_id, 'assignment_type', v_a.assignment_type)
  );

  return public.my_assignment_detail(v_a.id);
end;
$$;

-- Declining an open offer hides it from this volunteer. Declining your own accepted assignment (before the
-- trip starts) puts it back on offer for everyone else.
create or replace function public.decline_assignment(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid      uuid := auth.uid();
  v_p        public.profiles%rowtype;
  v_a        public.assignments%rowtype;
  v_req_id   uuid;
  v_released boolean := false;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select request_id into v_req_id from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform 1 from public.requests where id = v_req_id for update;

  select * into v_a from public.assignments where id = p_id for update;

  if v_a.volunteer_id = v_uid then
    if v_a.state <> 'accepted' then raise exception 'invalid_state'; end if;
    update public.assignments
       set volunteer_id = null, state = 'offered', accepted_at = null,
           declined_by = array_append(declined_by, v_uid)
     where id = p_id;
    update public.requests
       set status = 'awaiting_assignment', updated_at = now()
     where id = v_req_id and status = 'assigned';
    v_released := true;

  elsif v_a.state = 'offered' and v_a.volunteer_id is null
        and not (v_uid = any (v_a.declined_by))
        and public._tier_open_to(v_a.required_tier, v_p.categories, v_a.escalate_at) then
    update public.assignments set declined_by = array_append(declined_by, v_uid) where id = p_id;

  else
    raise exception 'not_found';
  end if;

  insert into public.assignment_events (assignment_id, event_type, actor_id, payload)
  values (p_id, 'declined', v_uid, jsonb_build_object('released', v_released));

  perform public.append_audit_log(
    'assignment_declined', v_uid, 'assignment', p_id,
    jsonb_build_object('request_id', v_req_id, 'released', v_released)
  );

  return jsonb_build_object('id', p_id, 'released', v_released);
end;
$$;

revoke all on function public.create_assignments(uuid) from public, anon, authenticated;
revoke all on function public.my_offers() from public, anon, authenticated;
revoke all on function public.my_assignment_detail(uuid) from public, anon, authenticated;
revoke all on function public.claim_assignment(uuid) from public, anon, authenticated;
revoke all on function public.decline_assignment(uuid) from public, anon, authenticated;

grant execute on function public.create_assignments(uuid) to authenticated;
grant execute on function public.my_offers() to authenticated;
grant execute on function public.my_assignment_detail(uuid) to authenticated;
grant execute on function public.claim_assignment(uuid) to authenticated;
grant execute on function public.decline_assignment(uuid) to authenticated;