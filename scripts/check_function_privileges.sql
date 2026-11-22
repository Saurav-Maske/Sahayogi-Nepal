-- Run in the Supabase SQL editor (or psql) after every `supabase db push`.
-- Query 1 returns ONLY violations: zero rows means the "Function privileges" matrix row passes.
-- Query 2 lists every function in public with who can execute it, for the Studio screenshot.

-- 1. Violations
with fn as (
  select p.oid, p.oid::regprocedure::text as signature, p.proname::text as name,
         has_function_privilege('anon',          p.oid, 'execute') as anon_exec,
         has_function_privilege('authenticated', p.oid, 'execute') as auth_exec,
         has_function_privilege('service_role',  p.oid, 'execute') as service_exec
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend d
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
), allow as (
  select unnest(array['get_tracking', 'requester_get_otp', 'requester_update_pickup_qty',
                      'requester_confirm_delivery', 'map_markers', 'is_admin',
                      'register_public_device_token', 'get_district_config']) as name, true as for_anon
  union all
  select unnest(array['admin_list_requests', 'admin_approve_request', 'admin_decline_request',
                      'admin_dashboard_counts', 'create_assignments', 'my_offers', 'my_assignment_detail',
                      'claim_assignment', 'decline_assignment', 'update_assignment_state', 'driver_verify_otp',
                      'admin_map_markers', 'update_my_location', 'my_stats', 'register_device_token',
                      'admin_import_stock', 'admin_move_lot', 'admin_list_incidents',
                      'admin_resolve_incident', 'admin_list_audit', 'admin_inventory_reconcile',
                      'admin_list_reserve_levels', 'admin_set_reserve_level', 'driver_report_issue',
                      'nearby_offers', 'admin_receive_donation', 'admin_issue_otp']), false
)
select fn.signature,
       case
         when fn.anon_exec and not coalesce(a.for_anon, false) then 'anon can execute but should not'
         when fn.auth_exec and a.name is null                  then 'authenticated can execute but should not'
         when a.for_anon and not fn.anon_exec                  then 'anon should be able to execute'
         when a.name is not null and not fn.auth_exec          then 'authenticated should be able to execute'
       end as problem
  from fn
  left join allow a on a.name = fn.name
 where (fn.anon_exec and not coalesce(a.for_anon, false))
    or (fn.auth_exec and a.name is null)
    or (a.for_anon and not fn.anon_exec)
    or (a.name is not null and not fn.auth_exec)
 order by 1;

-- 2. Full listing
select p.oid::regprocedure::text                          as signature,
       has_function_privilege('anon',          p.oid, 'execute') as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
       has_function_privilege('service_role',  p.oid, 'execute') as service_role
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind in ('f', 'p')
   and not exists (select 1 from pg_depend d
                    where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
 order by anon desc, authenticated desc, 1;