-- Function privileges clean-up (issue 11).
--
-- Rule after this migration: every function in schema public is callable by service_role only,
-- unless it is one of the client RPCs listed in the two arrays below.
--   anon          : get_tracking, requester_get_otp, requester_update_pickup_qty,
--                   requester_confirm_delivery, map_markers, plus is_admin (see 1.)
--   authenticated : the anon list plus the other 20 RPCs of parts 1-5
--
-- The RPCs of parts 1-5 already carry their own revoke/grant and are not touched here.
-- This file only fixes the older helpers that were created with the default PUBLIC execute right,
-- then sweeps for anything else, then fails the migration if the end state is wrong.
-- Safe to run more than once.

-- 1. is_admin()
-- RLS policies (profiles, requests, lots, audit, ...) and the volunteer-docs storage policy call it as
-- the requesting role, so anon and authenticated must keep execute or those policies would raise
-- "permission denied for function is_admin" instead of returning no rows. It only reads the caller's
-- own profile row and returns false for anon, so exposing it reveals nothing.
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;

-- 2. Audit helpers: service_role only
revoke all on function public.audit_row_hash(text, text, uuid, text, uuid, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.audit_row_hash(text, text, uuid, text, uuid, jsonb, timestamptz)
  to service_role;

-- Called by pg_cron (as postgres) and by scripts/seed_extra.mjs through the service role.
revoke all on function public.fn_export_latest_audit_hash() from public, anon, authenticated;
grant execute on function public.fn_export_latest_audit_hash() to service_role;

-- 3. Trigger functions. PostgreSQL checks EXECUTE only when a trigger is created, not when it fires,
-- so nobody needs a grant for the triggers to keep working.
revoke all on function public.fn_audit_logs_hash_chain()            from public, anon, authenticated;
revoke all on function public.fn_audit_logs_append_only()           from public, anon, authenticated;
revoke all on function public.fn_assignment_sync_driver_location()   from public, anon, authenticated;
revoke all on function public.auto_assign_request_district_id()     from public, anon, authenticated;

-- 4. Sweep: anything else in public that is not a client RPC (for example the push helpers
-- push_claim_batch, push_recipients and the _push_enqueue trigger function, or the email OTP helpers)
-- becomes service_role only. Functions that belong to an extension are skipped.
do $$
declare
  r record;
  v_client text[] := array[
    -- anon and authenticated
    'get_tracking', 'requester_get_otp', 'requester_update_pickup_qty',
    'requester_confirm_delivery', 'map_markers', 'is_admin',
    -- authenticated only
    'admin_list_requests', 'admin_approve_request', 'admin_decline_request', 'admin_dashboard_counts',
    'create_assignments', 'my_offers', 'my_assignment_detail', 'claim_assignment', 'decline_assignment',
    'update_assignment_state', 'driver_verify_otp',
    'admin_map_markers', 'update_my_location', 'my_stats', 'register_device_token',
    'admin_import_stock', 'admin_move_lot', 'admin_list_incidents', 'admin_resolve_incident',
    'admin_list_audit'
  ];
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       and p.proname::text <> all (v_client)
       and not exists (
             select 1 from pg_depend d
              where d.classid = 'pg_proc'::regclass
                and d.objid = p.oid
                and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;
end
$$;

-- 5. Check the end state. If anything is off, the whole migration rolls back.
do $$
declare
  v_anon text[] := array[
    'get_tracking', 'requester_get_otp', 'requester_update_pickup_qty',
    'requester_confirm_delivery', 'map_markers', 'is_admin'
  ];
  v_auth text[];
  v_bad  text;
begin
  v_auth := v_anon || array[
    'admin_list_requests', 'admin_approve_request', 'admin_decline_request', 'admin_dashboard_counts',
    'create_assignments', 'my_offers', 'my_assignment_detail', 'claim_assignment', 'decline_assignment',
    'update_assignment_state', 'driver_verify_otp',
    'admin_map_markers', 'update_my_location', 'my_stats', 'register_device_token',
    'admin_import_stock', 'admin_move_lot', 'admin_list_incidents', 'admin_resolve_incident',
    'admin_list_audit'
  ];

  -- anon may execute nothing outside its list
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend d
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'execute')
     and p.proname::text <> all (v_anon);
  if v_bad is not null then
    raise exception 'function privileges: anon can still execute: %', v_bad;
  end if;

  -- authenticated may execute nothing outside its list
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend d
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname::text <> all (v_auth);
  if v_bad is not null then
    raise exception 'function privileges: authenticated can still execute: %', v_bad;
  end if;

  -- the public ones must still be reachable by anon (catches an accidental revoke)
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and p.proname::text = any (v_anon)
     and not has_function_privilege('anon', p.oid, 'execute');
  if v_bad is not null then
    raise exception 'function privileges: anon lost access to: %', v_bad;
  end if;
end
$$;