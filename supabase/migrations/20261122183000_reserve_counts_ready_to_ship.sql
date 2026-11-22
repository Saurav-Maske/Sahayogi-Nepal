-- E6: the reserve alert now counts only stock that can actually be approved: lots in phase ready_to_ship,
-- minus what is already reserved. Newly donated lots ('received') and lots in 'processing' count after the
-- admin moves them to ready_to_ship (same rule as the inventory_available view).
create or replace function public._reserve_stock(p_item public.item_type)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(sum(l.quantity - l.reserved_qty), 0)
    from public.inventory_lots l
   where l.item_type = p_item
     and l.phase = 'ready_to_ship';
$$;

-- Re-set the flags from the new rule without sending any alert.
update public.inventory_reserve_levels r
   set below_reserve = (r.min_qty > 0 and public._reserve_stock(r.item_type) < r.min_qty);