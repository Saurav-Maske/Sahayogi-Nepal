-- Move the central inventory hub from the Kathmandu placeholder to the real hub: FWU-SOE, Kanchanpur.
--
-- Same point as the repository seeded in 20261121233149_central_repository_locations.sql
-- (28.954657907336678, 80.17888176615499, given as latitude, longitude).
--
-- Read by: create_assignments (route_snapshot hub point) and admin_map_markers ('hub').
-- Upsert, so it also works if the 'central_inventory' row was deleted by hand.
-- The key is not public (the 'district' key is the only one the app may read).

insert into public.app_settings (key, value) values (
  'central_inventory',
  '{"name":"FWU-SOE","lat":28.954657907336678,"lng":80.17888176615499,"address_note":"FWU-SOE central inventory, Kanchanpur"}'::jsonb
) on conflict (key) do update set value = excluded.value;

-- Assignments that already exist keep a copy of the old hub inside route_snapshot. Replace the hub point
-- on every assignment that is not finished, so drivers do not get routed to Kathmandu.
-- The hub point is the element with label 'central inventory' (see create_assignments).
update public.assignments a
   set route_snapshot = (
         select coalesce(jsonb_agg(
                  case when e.elem->>'label' = 'central inventory'
                       then jsonb_build_object(
                              'label', 'central inventory',
                              'lat', (h.value->>'lat')::double precision,
                              'lng', (h.value->>'lng')::double precision)
                       else e.elem
                  end
                  order by e.ord), '[]'::jsonb)
           from jsonb_array_elements(a.route_snapshot) with ordinality as e(elem, ord)
       )
  from public.app_settings h
 where h.key = 'central_inventory'
   and a.state not in ('delivered', 'declined', 'expired', 'cancelled', 'disputed')
   and a.route_snapshot @> '[{"label":"central inventory"}]'::jsonb;