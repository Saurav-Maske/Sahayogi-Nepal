-- A volunteer can review the requests they submitted while signed in. This
-- exposes only their own request summaries; tracking tokens remain client-only.
create or replace function public.my_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform 1 from public.profiles
   where id = v_uid and role = 'volunteer' and account_status = 'active';
  if not found then raise exception 'forbidden'; end if;

  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select r.created_at,
             jsonb_build_object(
               'public_ref', r.public_ref,
               'kind', r.kind,
               'status', r.status,
               'urgency', r.urgency,
               'district', d.name,
               'created_at', r.created_at,
               'approved_at', r.approved_at,
               'picked_up_at', r.picked_up_at,
               'fulfilled_at', r.fulfilled_at,
               'volunteers_needed', r.volunteers_needed,
               'items', coalesce((
                 select jsonb_agg(jsonb_build_object(
                   'item_type', i.item_type,
                   'requested_qty', i.requested_qty,
                   'approved_qty', i.approved_qty,
                   'donor_qty', i.donor_qty,
                   'confirmed_qty', i.confirmed_qty,
                   'unit', i.unit
                 ))
                   from public.request_items i
                  where i.request_id = r.id
               ), '[]'::jsonb)
             ) as row_data
        from public.requests r
        left join public.districts d on d.id = r.district_id
       where r.requester_profile_id = v_uid
    ) own_requests;

  return v_rows;
end;
$$;

revoke all on function public.my_requests() from public, anon, authenticated;
grant execute on function public.my_requests() to authenticated;
