-- Part 1: admin request review. Called by the admin app with the admin JWT; is_admin() is checked inside.
-- Errors are plain codes in error.message:
--   forbidden | not_found | invalid_state | invalid_status | invalid_kind | invalid_items | nothing_approved
--   insufficient_stock (detail = item_type) | invalid_reason

create or replace function public.admin_list_requests(p_status text default null, p_kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_status request_status;
  v_kind   request_kind;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  if p_status is not null then
    begin
      v_status := p_status::request_status;
    exception when invalid_text_representation then
      raise exception 'invalid_status';
    end;
  end if;
  if p_kind is not null then
    begin
      v_kind := p_kind::request_kind;
    exception when invalid_text_representation then
      raise exception 'invalid_kind';
    end;
  end if;

  return coalesce((
    select jsonb_agg(q.j order by q.urg, q.created_at)
    from (
      select
        case r.urgency when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end as urg,
        r.created_at,
        jsonb_build_object(
          'id', r.id,
          'public_ref', r.public_ref,
          'kind', r.kind,
          'status', r.status,
          'requester_name', r.requester_name,
          'requester_phone', r.requester_phone,
          'urgency', r.urgency,
          'notes', r.notes,
          'address_note', r.address_note,
          'volunteers_needed', r.volunteers_needed,
          'decline_reason', r.decline_reason,
          'district', d.name,
          'lat', st_y(r.location::geometry),
          'lng', st_x(r.location::geometry),
          'created_at', r.created_at,
          'approved_at', r.approved_at,
          'picked_up_at', r.picked_up_at,
          'fulfilled_at', r.fulfilled_at,
          'items', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'id', i.id, 'item_type', i.item_type, 'unit', i.unit,
              'requested_qty', i.requested_qty, 'approved_qty', i.approved_qty,
              'donor_qty', i.donor_qty, 'confirmed_qty', i.confirmed_qty
            ) order by i.item_type, i.id), '[]'::jsonb)
            from public.request_items i where i.request_id = r.id
          ),
          'assignments', (
            select jsonb_build_object(
              'total', count(*),
              'open', count(*) filter (where a.state = 'offered' and a.volunteer_id is null),
              'claimed', count(*) filter (where a.volunteer_id is not null)
            )
            from public.assignments a where a.request_id = r.id
          )
        ) as j
      from public.requests r
      left join public.districts d on d.id = r.district_id
      where (v_status is null or r.status = v_status)
        and (v_kind is null or r.kind = v_kind)
      order by 1, r.created_at
      limit 500
    ) q
  ), '[]'::jsonb);
end;
$$;

-- p_items: optional [{ "item_id": uuid, "approved_qty": number }]. Items left out are approved at requested_qty.
-- Stock is reserved only for resource_request, FIFO over ready_to_ship lots. Lots are locked in a fixed order
-- (item_type, then created_at, id) so parallel approvals cannot deadlock, and any shortfall rolls everything back.
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
        for v_lot in
          select l.id
            from public.inventory_lots l
           where l.phase = 'ready_to_ship' and l.item_type = v_item.item_type and l.quantity > l.reserved_qty
           order by l.created_at, l.id
           for update
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

create or replace function public.admin_decline_request(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_req    public.requests%rowtype;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if char_length(v_reason) not between 2 and 300 then raise exception 'invalid_reason'; end if;

  update public.requests
     set status = 'declined', decline_reason = v_reason, updated_at = now()
   where id = p_id and status = 'pending_admin_review'
  returning * into v_req;

  if not found then
    if exists (select 1 from public.requests where id = p_id) then
      raise exception 'invalid_state';
    end if;
    raise exception 'not_found';
  end if;

  perform public.append_audit_log(
    'request_declined', v_admin, 'request', p_id,
    jsonb_build_object('kind', v_req.kind, 'public_ref', v_req.public_ref)
  );

  return jsonb_build_object('request_id', p_id, 'status', 'declined');
end;
$$;

create or replace function public.admin_dashboard_counts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  return jsonb_build_object(
    'requests_by_status', coalesce((
      select jsonb_object_agg(s.status::text, s.n)
        from (select status, count(*) as n from public.requests group by status) s
    ), '{}'::jsonb),
    'assignments_by_state', coalesce((
      select jsonb_object_agg(s.state::text, s.n)
        from (select state, count(*) as n from public.assignments group by state) s
    ), '{}'::jsonb),
    'open_offers', (select count(*) from public.assignments where state = 'offered' and volunteer_id is null),
    'open_incidents', (select count(*) from public.incidents where status in ('open', 'under_review')),
    'pending_applications', (
      select count(*) from public.volunteer_applications where review_status in ('submitted', 'under_review')
    ),
    'stock_available', coalesce((
      select jsonb_object_agg(a.item_type::text, a.available_qty) from public.inventory_available a
    ), '{}'::jsonb)
  );
end;
$$;

revoke all on function public.admin_list_requests(text, text) from public, anon, authenticated;
revoke all on function public.admin_approve_request(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.admin_decline_request(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_dashboard_counts() from public, anon, authenticated;

grant execute on function public.admin_list_requests(text, text) to authenticated;
grant execute on function public.admin_approve_request(uuid, jsonb) to authenticated;
grant execute on function public.admin_decline_request(uuid, text) to authenticated;
grant execute on function public.admin_dashboard_counts() to authenticated;