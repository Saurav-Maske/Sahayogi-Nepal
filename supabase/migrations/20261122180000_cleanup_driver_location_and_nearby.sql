-- E2: keep one driver-location system (RPC update_my_location -> volunteer_locations).
-- The app, get_tracking and admin_map_markers already use it. Remove the second system.
drop trigger  if exists trg_assignment_sync_driver_location on public.assignments;
drop function if exists public.fn_assignment_sync_driver_location();
drop view     if exists public.assignment_current_event;
drop table    if exists public.driver_latest_location;

-- E3: get_nearby_requests was an edge function only (nothing in SQL). Replaced by nearby_offers.
-- Nothing to drop in the database for it.