-- Run in the Supabase SQL editor after `supabase db push`. Every query should return ZERO rows
-- (query 5 is the summary you read by eye).

-- 1. Lots, reservations or movements without a repository
select 'lot' as kind, id from public.inventory_lots where inventory_repository_id is null
union all select 'reservation', id from public.inventory_reservations where inventory_repository_id is null
union all select 'movement', id from public.inventory_movements where inventory_repository_id is null;

-- 2. Reservation repository differs from its lot's repository
select r.id from public.inventory_reservations r
  join public.inventory_lots l on l.id = r.lot_id
 where r.inventory_repository_id <> l.inventory_repository_id;

-- 3. Lot reserved_qty differs from the sum of its active reservations
select l.id, l.reserved_qty, coalesce(s.q, 0) as active_reservations
  from public.inventory_lots l
  left join (select lot_id, sum(quantity) q from public.inventory_reservations where status = 'active' group by lot_id) s
    on s.lot_id = l.id
 where l.reserved_qty <> coalesce(s.q, 0);

-- 4. Active reservations on requests that are already finished
select r.id, rq.status
  from public.inventory_reservations r
  join public.request_items i on i.id = r.request_item_id
  join public.requests rq on rq.id = i.request_id
 where r.status = 'active' and rq.status in ('fulfilled', 'declined', 'cancelled');

-- 5. Summary per repository
select * from public.inventory_available_by_repository order by repository_name, item_type;