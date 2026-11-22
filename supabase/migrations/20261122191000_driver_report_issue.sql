-- C9: the driver can refuse a donation pickup or report that the items do not match, and it opens an incident.
-- The job is released (back to offered, this driver excluded) so another driver can take it, and the request
-- goes back to awaiting_assignment. The incident keeps the reporting driver, because the assignment no longer does.

alter table public.incidents add column if not exists reported_by_volunteer_id uuid references public.profiles (id);

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
  if v_a.assignment_type <> 'pickup' or v_a.state not in ('accepted', 'en_route_to_pickup') then
    raise exception 'invalid_state';
  end if;

  insert into public.incidents (assignment_id, request_id, incident_type, reporter_note, reported_by_volunteer_id)
  values (p_id, v_req_id, v_type, v_note, v_uid)
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
  values (p_id, 'incident_opened', v_uid, jsonb_build_object('type', v_type, 'incident_id', v_inc, 'released', true));

  perform public.append_audit_log(
    'incident_opened', v_uid, 'incident', v_inc,
    jsonb_build_object('request_id', v_req_id, 'assignment_id', p_id, 'type', v_type)
  );

  return jsonb_build_object('incident_id', v_inc, 'released', true);
end;
$$;

revoke all on function public.driver_report_issue(uuid, text, text) from public, anon, authenticated;
grant execute on function public.driver_report_issue(uuid, text, text) to authenticated;

-- Admin list: adds "reporter" (the driver who reported), because the assignment no longer holds the driver.
create or replace function public.admin_list_incidents(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if v_status is not null and v_status not in ('open', 'under_review', 'resolved', 'dismissed') then
    raise exception 'invalid_status';
  end if;

  return coalesce((
    select jsonb_agg(q.j order by q.rnk, q.created_at desc)
      from (
        select case i.status when 'open' then 0 when 'under_review' then 1 else 2 end as rnk,
               i.created_at,
               jsonb_build_object(
                 'id', i.id,
                 'status', i.status,
                 'incident_type', i.incident_type,
                 'reporter_note', i.reporter_note,
                 'reported_shortfall', i.reported_shortfall,
                 'resolution', i.resolution,
                 'admin_notes', i.admin_notes,
                 'created_at', i.created_at,
                 'request', case when r.id is not null then jsonb_build_object(
                     'id', r.id,
                     'public_ref', r.public_ref,
                     'kind', r.kind,
                     'status', r.status,
                     'requester_name', r.requester_name,
                     'requester_phone', r.requester_phone,
                     'district', d.name,
                     'items', (
                       select coalesce(jsonb_agg(jsonb_build_object(
                         'id', it.id, 'item_type', it.item_type, 'unit', it.unit,
                         'requested_qty', it.requested_qty, 'approved_qty', it.approved_qty,
                         'confirmed_qty', it.confirmed_qty
                       ) order by it.item_type, it.id), '[]'::jsonb)
                       from public.request_items it where it.request_id = r.id
                     )
                   ) end,
                 'assignment', case when a.id is not null then jsonb_build_object(
                     'id', a.id,
                     'assignment_type', a.assignment_type,
                     'state', a.state,
                     'volunteer_id', a.volunteer_id,
                     'volunteer_name', p.full_name,
                     'volunteer_phone', p.phone
                   ) end,
                 'reporter', case when rp.id is not null then jsonb_build_object(
                     'id', rp.id, 'name', rp.full_name, 'phone', rp.phone) end
               ) as j
          from public.incidents i
          left join public.requests r on r.id = i.request_id
          left join public.districts d on d.id = r.district_id
          left join public.assignments a on a.id = i.assignment_id
          left join public.profiles p on p.id = a.volunteer_id
          left join public.profiles rp on rp.id = i.reported_by_volunteer_id
         where v_status is null or i.status = v_status
         order by 1, i.created_at desc
         limit 500
      ) q
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_incidents(text) from public, anon, authenticated;
grant execute on function public.admin_list_incidents(text) to authenticated;