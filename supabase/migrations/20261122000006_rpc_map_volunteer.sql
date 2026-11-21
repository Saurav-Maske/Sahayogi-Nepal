-- Part 4: map and volunteer extras. Independent of Parts 2 and 3 (reads the same tables, adds no state).
-- Errors: unauthorized | forbidden | not_found | invalid_state | invalid_location | invalid_token | invalid_platform
--
-- map_markers is the only public (anon) function here. It never returns a name, phone, id or public_ref, and
-- coordinates are rounded to 2 decimals (about 1 km).

-- Public map. One marker per request, in exactly one layer:
--   fulfilled : status fulfilled, fulfilled_at within the last 12 h
--   pickup    : donation picked up within the last 6 h
--   donation  : approved donation still waiting for pickup
--   need      : approved request of any other kind that is not finished
-- Pending, declined and cancelled requests are never shown. Older pickups and fulfilled requests drop off.
-- 'key' is a stable one-way hash of the request id so the app can diff markers without learning real ids.
create or replace function public.map_markers()
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(jsonb_agg(q.j order by q.ts desc), '[]'::jsonb)
    from (
      select s.ts,
             jsonb_build_object(
               'key', left(encode(digest(s.id::text, 'sha256'), 'hex'), 12),
               'layer', s.layer,
               'kind', s.kind,
               'urgency', s.urgency,
               'lat', s.lat,
               'lng', s.lng,
               'item_types', s.item_types,
               'at', s.ts
             ) as j
        from (
          select r.id, r.kind, r.urgency,
                 round(st_y(r.location::geometry)::numeric, 2) as lat,
                 round(st_x(r.location::geometry)::numeric, 2) as lng,
                 case
                   when r.status = 'fulfilled' and r.fulfilled_at >= now() - interval '12 hours' then 'fulfilled'
                   when r.kind = 'donation_offer' and r.picked_up_at >= now() - interval '6 hours'
                        and r.status not in ('pending_admin_review', 'declined', 'cancelled') then 'pickup'
                   when r.kind = 'donation_offer' and r.picked_up_at is null
                        and r.status in ('approved', 'awaiting_assignment', 'assigned', 'in_progress') then 'donation'
                   when r.kind <> 'donation_offer'
                        and r.status in ('approved', 'awaiting_assignment', 'assigned', 'in_progress') then 'need'
                 end as layer,
                 case
                   when r.status = 'fulfilled' and r.fulfilled_at >= now() - interval '12 hours' then r.fulfilled_at
                   when r.kind = 'donation_offer' and r.picked_up_at >= now() - interval '6 hours' then r.picked_up_at
                   else coalesce(r.approved_at, r.created_at)
                 end as ts,
                 (select coalesce(jsonb_agg(distinct i.item_type::text), '[]'::jsonb)
                    from public.request_items i where i.request_id = r.id) as item_types
            from public.requests r
        ) s
       where s.layer is not null
       order by s.ts desc
       limit 500
    ) q;
$$;

-- Admin map: exact positions plus live volunteer positions and the hub.
-- requests: everything still open (including pending review) and fulfilled in the last 12 h.
-- volunteers: assignments that are in progress and have reported a position in the last 30 minutes.
create or replace function public.admin_map_markers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  return jsonb_build_object(
    'hub', (select s.value from public.app_settings s where s.key = 'central_inventory'),
    'requests', coalesce((
      select jsonb_agg(q.j order by q.created_at desc)
        from (
          select r.created_at,
                 jsonb_build_object(
                   'id', r.id,
                   'public_ref', r.public_ref,
                   'kind', r.kind,
                   'status', r.status,
                   'urgency', r.urgency,
                   'requester_name', r.requester_name,
                   'district', d.name,
                   'lat', st_y(r.location::geometry),
                   'lng', st_x(r.location::geometry),
                   'open_incidents', (select count(*) from public.incidents i
                                       where i.request_id = r.id and i.status in ('open', 'under_review')),
                   'assignments', (select jsonb_build_object(
                                          'total', count(*),
                                          'claimed', count(*) filter (where a.volunteer_id is not null))
                                     from public.assignments a where a.request_id = r.id),
                   'created_at', r.created_at,
                   'updated_at', r.updated_at
                 ) as j
            from public.requests r
            left join public.districts d on d.id = r.district_id
           where r.status in ('pending_admin_review', 'approved', 'awaiting_assignment', 'assigned',
                              'in_progress', 'partially_fulfilled')
              or (r.status = 'fulfilled' and r.fulfilled_at >= now() - interval '12 hours')
           order by r.created_at desc
           limit 1000
        ) q
    ), '[]'::jsonb),
    'volunteers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignment_id', a.id,
               'request_id', a.request_id,
               'public_ref', r.public_ref,
               'assignment_type', a.assignment_type,
               'state', a.state,
               'volunteer_id', a.volunteer_id,
               'volunteer_name', p.full_name,
               'volunteer_phone', p.phone,
               'lat', l.lat,
               'lng', l.lng,
               'updated_at', l.updated_at
             ) order by l.updated_at desc)
        from public.volunteer_locations l
        join public.assignments a on a.id = l.assignment_id
        join public.requests r on r.id = a.request_id
        left join public.profiles p on p.id = a.volunteer_id
       where a.state in ('accepted', 'en_route_to_pickup', 'picked_up', 'en_route_to_destination')
         and l.updated_at >= now() - interval '30 minutes'
    ), '[]'::jsonb)
  );
end;
$$;

-- The volunteer's live position for one of their own assignments. volunteer_locations holds one row per
-- assignment (primary key), so this is an upsert. Requesters see it through get_tracking only while the
-- assignment is en_route_*. Not written to the audit log on purpose: it is called every few seconds.
create or replace function public.update_my_location(p_id uuid, p_lat double precision, p_lng double precision)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_a   public.assignments%rowtype;
  v_req public.request_status;
  v_at  timestamptz;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform 1 from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  -- NaN and infinity fail BETWEEN, so they are rejected here too (roughly Nepal's bounding box).
  if p_lat is null or p_lng is null
     or not (p_lat between 26.3 and 30.5) or not (p_lng between 80.0 and 88.3) then
    raise exception 'invalid_location';
  end if;

  select * into v_a from public.assignments where id = p_id and volunteer_id = v_uid;
  if not found then raise exception 'not_found'; end if;

  select status into v_req from public.requests where id = v_a.request_id;
  if v_a.state not in ('accepted', 'en_route_to_pickup', 'picked_up', 'en_route_to_destination')
     or v_req not in ('assigned', 'in_progress') then
    raise exception 'invalid_state';
  end if;

  insert into public.volunteer_locations (assignment_id, lat, lng, updated_at)
  values (p_id, p_lat, p_lng, now())
  on conflict (assignment_id) do update
    set lat = excluded.lat, lng = excluded.lng, updated_at = excluded.updated_at
  returning updated_at into v_at;

  return jsonb_build_object('ok', true, 'updated_at', v_at);
end;
$$;

-- Numbers for the volunteer's own profile screen. 'declined_offers' counts offers this volunteer declined,
-- including their own accepted assignments they released.
create or replace function public.my_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform 1 from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  return (
    select jsonb_build_object(
      'claimed_total', count(*),
      'active', count(*) filter (where a.state in ('accepted', 'en_route_to_pickup', 'picked_up', 'en_route_to_destination')),
      'completed', count(*) filter (where a.state = 'delivered'),
      'disputed', count(*) filter (where a.state = 'disputed'),
      'completed_last_30_days', count(*) filter (where a.state = 'delivered' and a.completed_at >= now() - interval '30 days'),
      'last_completed_at', max(a.completed_at) filter (where a.state = 'delivered'),
      'completed_by_type', coalesce((
        select jsonb_object_agg(t.assignment_type::text, t.n)
          from (select x.assignment_type, count(*) as n
                  from public.assignments x
                 where x.volunteer_id = v_uid and x.state = 'delivered'
                 group by x.assignment_type) t
      ), '{}'::jsonb),
      'declined_offers', (select count(*) from public.assignments d where v_uid = any (d.declined_by))
    )
    from public.assignments a
    where a.volunteer_id = v_uid
  );
end;
$$;

-- Stores the device's push token for this volunteer. A token belongs to one device, so if it is already
-- stored it moves to the caller (same phone, new login). Keeps the 10 most recently seen tokens per volunteer.
create or replace function public.register_device_token(p_token text, p_platform text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_token text := btrim(coalesce(p_token, ''));
  v_id    uuid;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform 1 from public.profiles where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  if char_length(v_token) not between 20 and 4096 or v_token ~ '\s' then raise exception 'invalid_token'; end if;
  if p_platform is null or p_platform not in ('android', 'ios', 'web') then raise exception 'invalid_platform'; end if;

  insert into public.device_tokens (profile_id, token, platform, last_seen_at)
  values (v_uid, v_token, p_platform, now())
  on conflict (token) do update
    set profile_id = excluded.profile_id, platform = excluded.platform, last_seen_at = now()
  returning id into v_id;

  delete from public.device_tokens
   where id in (select t.id from public.device_tokens t
                 where t.profile_id = v_uid
                 order by t.last_seen_at desc, t.id
                offset 10);

  return jsonb_build_object('id', v_id, 'platform', p_platform);
end;
$$;

revoke all on function public.map_markers() from public, anon, authenticated;
revoke all on function public.admin_map_markers() from public, anon, authenticated;
revoke all on function public.update_my_location(uuid, double precision, double precision) from public, anon, authenticated;
revoke all on function public.my_stats() from public, anon, authenticated;
revoke all on function public.register_device_token(text, text) from public, anon, authenticated;

grant execute on function public.map_markers() to anon, authenticated;
grant execute on function public.admin_map_markers() to authenticated;
grant execute on function public.update_my_location(uuid, double precision, double precision) to authenticated;
grant execute on function public.my_stats() to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;