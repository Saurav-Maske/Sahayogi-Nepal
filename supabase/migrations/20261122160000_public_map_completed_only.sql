-- Public "Explore" map for people who are not logged in: completed work only.
--
-- Two layers, nothing else:
--   pickup    (blue)  : a DONATION we have received from a user. The driver has entered the donor's OTP, so
--                       requests.picked_up_at is set and it is within the last 6 hours. It stays in this layer
--                       even after the driver has dropped it at the hub (the old function moved it to the green
--                       layer at that moment, which was wrong).
--   fulfilled (green) : a RESOURCE REQUEST we have delivered to the requester (fulfilled_at within the last 12 h).
--                       Only kind = resource_request. Manpower, healthcare, transport and donation requests
--                       never appear here.
--
-- Never shown to the public any more: requests waiting for admin approval, approved or open requests, requests
-- that are being picked up or delivered right now, declined and cancelled requests (the old 'donation' and
-- 'need' layers are gone).
--
-- Same output shape as before: array of { key, layer, kind, urgency, lat, lng, item_types, at }, newest first,
-- max 500. Coordinates rounded to 2 decimals (about 1 km). No name, phone, id or public_ref.
-- A delivery that was reported short by the requester (status partially_fulfilled) still counts as delivered.

create or replace function public.map_markers()
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(jsonb_agg(q.j order by q.ts desc), '[]'::jsonb)
    from (
      select s.ts,
             jsonb_build_object(
               'key', left(encode(digest(s.id::text, 'sha256'), 'hex'), 12),
               'layer', s.layer,
               'kind', s.kind,
               'urgency', s.urgency,
               'lat', s.lat,
               'lng', s.lng,
               'item_types', s.item_types,
               'at', s.ts
             ) as j
        from (
          select r.id, r.kind, r.urgency,
                 round(st_y(r.location::geometry)::numeric, 2) as lat,
                 round(st_x(r.location::geometry)::numeric, 2) as lng,
                 case
                   -- blue: donation received from the donor in the last 6 h
                   when r.kind = 'donation_offer'
                        and r.picked_up_at >= now() - interval '6 hours'
                        and r.status not in ('pending_admin_review', 'declined', 'cancelled')
                     then 'pickup'
                   -- green: resource request delivered in the last 12 h
                   when r.kind = 'resource_request'
                        and r.status in ('fulfilled', 'partially_fulfilled')
                        and r.fulfilled_at >= now() - interval '12 hours'
                     then 'fulfilled'
                 end as layer,
                 case
                   when r.kind = 'donation_offer' then r.picked_up_at
                   else r.fulfilled_at
                 end as ts,
                 (select coalesce(jsonb_agg(distinct i.item_type::text), '[]'::jsonb)
                    from public.request_items i where i.request_id = r.id) as item_types
            from public.requests r
           where (r.kind = 'donation_offer'   and r.picked_up_at >= now() - interval '6 hours')
              or (r.kind = 'resource_request' and r.fulfilled_at >= now() - interval '12 hours')
        ) s
       where s.layer is not null
       order by s.ts desc
       limit 500
    ) q;
$$;

-- create or replace keeps the existing privileges; stated again so this file is correct on its own.
revoke all on function public.map_markers() from public, anon, authenticated;
grant execute on function public.map_markers() to anon, authenticated;