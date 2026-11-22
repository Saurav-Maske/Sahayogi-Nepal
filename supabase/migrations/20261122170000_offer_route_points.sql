-- Route preview for volunteers, step 1 of 2 (step 2 is the Edge Function get-offer-route).
--
-- Before a driver accepts, my_offers / my_assignment_detail only show an approximate position (2 decimals,
-- about 1 km) and never the hub. A real route preview needs the exact points, so the points are looked up here,
-- on the server, and the Edge Function sends them straight to the routing service. The app only gets back the
-- route lines, distance and time, never the coordinates of the donor or requester.
--
-- offer_route_points(p_user, p_id) is SERVICE ROLE ONLY (revoked from anon and authenticated), because it
-- returns exact coordinates. The Edge Function checks the caller's JWT first and passes the user id in.
--
-- Who may ask (same rule as my_assignment_detail, so nobody can preview what they cannot see):
--   * an open offer: assignment offered, nobody holds it, request awaiting_assignment, caller has not declined
--     it, and the caller's categories fit the tier (_tier_open_to); or
--   * the caller's own assignment that is not finished (accepted, en route, picked up ...).
-- Anything else is 'not_found' (does not say whether the offer exists).
--
-- Points, in driving order AFTER the driver's own position (the Edge Function adds that):
--   donation_offer    : donor, central inventory
--   resource_request  : central inventory, requester
--   other kinds       : requester
-- The hub is read live from app_settings 'central_inventory', not from route_snapshot, so a moved hub is
-- picked up at once.
--
-- Errors: unauthorized | forbidden | not_found | hub_not_configured

create or replace function public.offer_route_points(p_user uuid, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_p      public.profiles%rowtype;
  v_a      public.assignments%rowtype;
  v_r      public.requests%rowtype;
  v_hub    jsonb;
  v_hub_pt jsonb;
  v_pt     jsonb;
  v_points jsonb;
begin
  if p_user is null then raise exception 'unauthorized'; end if;

  select * into v_p from public.profiles
   where id = p_user and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select * into v_a from public.assignments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  select * into v_r from public.requests where id = v_a.request_id;

  -- coalesce: volunteer_id is null on an open offer, so the first test is NULL there, and a NULL check
  -- would let the caller through. Anything that is not clearly true is refused.
  if not coalesce(
       (coalesce(v_a.volunteer_id = p_user, false)
         and v_a.state not in ('delivered', 'declined', 'expired', 'cancelled', 'disputed'))
    or (v_a.state = 'offered' and v_a.volunteer_id is null
         and v_r.status = 'awaiting_assignment'
         and not (p_user = any (coalesce(v_a.declined_by, '{}'::uuid[])))
         and coalesce(public._tier_open_to(v_a.required_tier, v_p.categories, v_a.escalate_at), false))
  , false) then
    raise exception 'not_found';
  end if;

  v_pt := jsonb_build_object(
    'label', case v_r.kind when 'donation_offer' then 'donor' else 'requester' end,
    'lat', st_y(v_r.location::geometry),
    'lng', st_x(v_r.location::geometry)
  );

  if v_r.kind in ('resource_request', 'donation_offer') then
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

  v_points := case v_r.kind
    when 'donation_offer'   then jsonb_build_array(v_pt, v_hub_pt)
    when 'resource_request' then jsonb_build_array(v_hub_pt, v_pt)
    else jsonb_build_array(v_pt)
  end;

  return jsonb_build_object(
    'kind', v_r.kind,
    'assignment_type', v_a.assignment_type,
    'points', v_points
  );
end;
$$;

-- Exact coordinates: service role only. New functions in public get execute for anon and authenticated by
-- default, so take it away explicitly (see 20261122000011_function_privileges.sql).
revoke all on function public.offer_route_points(uuid, uuid) from public, anon, authenticated;
grant execute on function public.offer_route_points(uuid, uuid) to service_role;