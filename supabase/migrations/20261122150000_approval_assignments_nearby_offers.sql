-- Every successful admin approval creates its volunteer assignments in the same transaction.
-- Keep the previous stock reservation and validation logic intact by wrapping its implementation.
alter function public.admin_approve_request(uuid, jsonb)
  rename to _admin_approve_request_without_assignments;

revoke all on function public._admin_approve_request_without_assignments(uuid, jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.admin_approve_request(p_id uuid, p_items jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_result jsonb;
  v_assignments jsonb;
begin
  v_result := public._admin_approve_request_without_assignments(p_id, p_items);
  v_assignments := public.create_assignments(p_id);

  return v_result || jsonb_build_object(
    'status', v_assignments->'status',
    'assignments', v_assignments->'assignments'
  );
end;
$$;

revoke all on function public.admin_approve_request(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_approve_request(uuid, jsonb) to authenticated;

-- This authenticated counterpart to the public map returns only open offers visible to this volunteer,
-- adding the assignment ID needed by the existing atomic claim_assignment operation.
create or replace function public.nearby_offers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_p public.profiles%rowtype;
  v_origin geography;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into v_p from public.profiles
   where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  if p_lat is null or p_lat not between -90 and 90
     or p_lng is null or p_lng not between -180 and 180
     or p_radius_km is null or p_radius_km not between 0.1 and 100 then
    raise exception 'invalid_location';
  end if;
  v_origin := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  return coalesce((
    select jsonb_agg(o.j order by o.distance_m, o.urg, o.offered_at)
    from (
      select
        case r.urgency when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end as urg,
        a.offered_at,
        st_distance(r.location::geography, v_origin) as distance_m,
        jsonb_build_object(
          'assignment_id', a.id,
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
          'distance_km', round((st_distance(r.location::geography, v_origin) / 1000)::numeric, 1),
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
        and not exists (
          select 1 from public.assignments b
           where b.request_id = a.request_id and b.volunteer_id = v_uid
             and b.state not in ('declined', 'expired', 'cancelled')
        )
        and st_dwithin(r.location::geography, v_origin, p_radius_km * 1000)
    ) o
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.nearby_offers(double precision, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.nearby_offers(double precision, double precision, double precision)
  to authenticated;
