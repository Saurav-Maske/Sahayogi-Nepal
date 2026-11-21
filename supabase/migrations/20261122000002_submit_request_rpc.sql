-- submit_request: creates a request AND its items in ONE transaction, enforces the per-phone rate limit
-- and the pilot-district bounds, and writes the audit row.
--
-- Called ONLY by the submit-request Edge Function with the service role. Clients get no execute right.
-- The raw tracking token never reaches the database: the function sends its SHA-256 hash.
--
-- Error contract: failures are raised as plain codes (error.message), which the Edge Function maps to HTTP:
--   invalid_kind | invalid_name | invalid_phone | invalid_location | outside_service_area | invalid_urgency
--   invalid_volunteers_needed | invalid_items | invalid_token_hash | too_many_requests

-- Supports the "5 per phone per hour" count. Compared on the last 10 digits so +97798... and 98... are one phone.
create index if not exists requests_phone_created_idx
  on public.requests (right(requester_phone, 10), created_at);

create or replace function public.submit_request(p jsonb, p_profile uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_kind       request_kind;
  v_name       text := btrim(coalesce(p->>'requester_name', ''));
  v_phone      text := regexp_replace(coalesce(p->>'requester_phone', ''), '[\s-]', '', 'g');
  v_urgency    text := coalesce(p->>'urgency', 'normal');
  v_hash       text := coalesce(p->>'tracking_token_hash', '');
  v_lat        double precision;
  v_lng        double precision;
  v_bounds     jsonb;
  v_volunteers int;
  v_count      numeric;
  v_items      jsonb;
  v_recent     int;
  v_req        requests%rowtype;
  v_district   text;
begin
  -- ---- validation (the Edge Function checks the same things first for friendly errors; this is the real boundary)
  begin
    v_kind := (p->>'kind')::request_kind;
  exception when invalid_text_representation then
    v_kind := null;
  end;
  if v_kind is null then raise exception 'invalid_kind'; end if;

  if char_length(v_name) not between 2 and 120 then raise exception 'invalid_name'; end if;
  if v_phone !~ '^(\+977)?9[6-8][0-9]{8}$' then raise exception 'invalid_phone'; end if;
  if v_urgency not in ('low', 'normal', 'high', 'critical') then raise exception 'invalid_urgency'; end if;
  if v_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_token_hash'; end if;

  if jsonb_typeof(p->'lat') is distinct from 'number' or jsonb_typeof(p->'lng') is distinct from 'number' then
    raise exception 'invalid_location';
  end if;
  v_lat := (p->>'lat')::double precision;
  v_lng := (p->>'lng')::double precision;
  -- Rough Nepal box first, then the pilot district's own bounds (app_settings 'district', seeded in 20261122000001).
  if v_lat not between 26.3 and 30.5 or v_lng not between 80.0 and 88.3 then
    raise exception 'invalid_location';
  end if;
  select value->'bounds' into v_bounds from public.app_settings where key = 'district';
  if v_bounds is not null and (
       v_lat < (v_bounds->>'south')::double precision or v_lat > (v_bounds->>'north')::double precision or
       v_lng < (v_bounds->>'west')::double precision  or v_lng > (v_bounds->>'east')::double precision) then
    raise exception 'outside_service_area';
  end if;

  if v_kind in ('manpower_request', 'healthcare_request', 'transport_request') then
    -- Separate checks on purpose: Postgres does not guarantee short-circuit order inside one OR.
    if jsonb_typeof(p->'volunteers_needed') is distinct from 'number' then
      raise exception 'invalid_volunteers_needed';
    end if;
    v_count := (p->>'volunteers_needed')::numeric;
    if v_count <> trunc(v_count) or v_count not between 1 and 100 then
      raise exception 'invalid_volunteers_needed';
    end if;
    v_volunteers := v_count::int;
  else
    v_items := p->'items';
    if jsonb_typeof(v_items) is distinct from 'array' then raise exception 'invalid_items'; end if;
    if jsonb_array_length(v_items) not between 1 and 20 then raise exception 'invalid_items'; end if;
  end if;

  -- ---- rate limit: max 5 requests per phone per hour. The advisory lock serialises concurrent submits for the
  -- same phone so two parallel calls cannot both read "4" and both insert.
  perform pg_advisory_xact_lock(hashtext('submit_request:' || right(v_phone, 10)));
  select count(*) into v_recent
    from public.requests
   where right(requester_phone, 10) = right(v_phone, 10)
     and created_at > now() - interval '1 hour';
  if v_recent >= 5 then raise exception 'too_many_requests'; end if;

  -- ---- insert request + items. Any failure below rolls back the whole call, so there is never a half-made request.
  insert into public.requests (
    kind, requester_name, requester_phone, requester_profile_id, location,
    address_note, urgency, notes, volunteers_needed, tracking_token_hash
  ) values (
    v_kind, v_name, v_phone, p_profile,
    st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography,   -- longitude first; district_id is set by trigger
    left(nullif(p->>'address_note', ''), 300), v_urgency, left(nullif(p->>'notes', ''), 1000),
    v_volunteers, v_hash
  ) returning * into v_req;

  if v_items is not null then
    begin
      insert into public.request_items (request_id, item_type, requested_qty, unit)
      select v_req.id, (e.item->>'item_type')::item_type, (e.item->>'qty')::numeric,
             left(coalesce(nullif(e.item->>'unit', ''), 'unit'), 20)
        from jsonb_array_elements(v_items) as e(item);
    exception when invalid_text_representation or check_violation or not_null_violation or numeric_value_out_of_range then
      raise exception 'invalid_items';
    end;
  end if;

  -- No phone number or name in the audit detail: the log is permanent and append-only.
  perform public.append_audit_log(
    'request_submitted', p_profile, 'request', v_req.id,
    jsonb_build_object('kind', v_req.kind, 'public_ref', v_req.public_ref)
  );

  select d.name into v_district from public.districts d where d.id = v_req.district_id;

  return jsonb_build_object(
    'request_id', v_req.id,
    'public_ref', v_req.public_ref,
    'status',     v_req.status,
    'district',   v_district
  );
end;
$$;

revoke all on function public.submit_request(jsonb, uuid) from public, anon, authenticated;
grant execute on function public.submit_request(jsonb, uuid) to service_role;
