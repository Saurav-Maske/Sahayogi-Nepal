-- C7: until the driver enters the pickup OTP, the donor may lower, raise, remove (qty 0) and add items.
-- p_items: [{ "item_id": uuid, "qty": n }]            change an existing item
--          [{ "item_type": text, "qty": n >= 1 }]     add a new item (only for a type not already on the request)
-- A raised or added item differs from the approved quantity, so driver_verify_otp already asks the driver to
-- confirm the changed quantities (reason quantity_changed) before the code is accepted.
create or replace function public.requester_update_pickup_qty(p_ref text, p_token text, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := public._request_id_by_token(p_ref, p_token);
  v_req  public.requests%rowtype;
  v_el   jsonb;
  v_type public.item_type;
  v_qty  numeric;
begin
  select * into v_req from public.requests where id = v_id for update;
  if v_req.kind <> 'donation_offer'
     or v_req.picked_up_at is not null
     or v_req.status not in ('approved', 'awaiting_assignment', 'assigned', 'in_progress') then
    raise exception 'invalid_state';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'invalid_items';
  end if;

  for v_el in select e from jsonb_array_elements(p_items) e loop
    if jsonb_typeof(v_el) <> 'object' or jsonb_typeof(v_el->'qty') is distinct from 'number' then
      raise exception 'invalid_items';
    end if;
    v_qty := (v_el->>'qty')::numeric;
    if v_qty < 0 or v_qty > 1000000 or v_qty <> trunc(v_qty) then raise exception 'invalid_quantity'; end if;
    if (v_el ? 'item_id') = (v_el ? 'item_type') then raise exception 'invalid_items'; end if;

    if v_el ? 'item_id' then
      if not exists (select 1 from public.request_items i where i.request_id = v_id and i.id::text = v_el->>'item_id') then
        raise exception 'invalid_items';
      end if;
      update public.request_items set donor_qty = v_qty
       where request_id = v_id and id::text = v_el->>'item_id';
    else
      begin
        v_type := (v_el->>'item_type')::public.item_type;
      exception when invalid_text_representation then
        raise exception 'invalid_items';
      end;
      if v_type is null or v_qty < 1
         or exists (select 1 from public.request_items i where i.request_id = v_id and i.item_type = v_type) then
        raise exception 'invalid_items';
      end if;
      -- approved_qty 0 = not approved by the admin; donor_qty differs from it, so the driver must confirm.
      insert into public.request_items (request_id, item_type, requested_qty, approved_qty, donor_qty, unit)
      values (v_id, v_type, v_qty, 0, v_qty, 'kit');
    end if;
  end loop;

  if (select count(*) from public.request_items where request_id = v_id) > 20
     or (select count(distinct coalesce(e->>'item_id', e->>'item_type')) from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
    raise exception 'invalid_items';
  end if;

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

revoke all on function public.requester_update_pickup_qty(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.requester_update_pickup_qty(text, text, jsonb) to anon, authenticated;