-- Every resource unit is a kit: unit is always 'kit' and every quantity is a whole number.

-- 1. Fix existing rows (only rows that are not already correct).
update public.request_items
   set unit = 'kit',
       requested_qty = greatest(1, round(requested_qty)),
       approved_qty  = round(approved_qty),
       donor_qty     = round(donor_qty),
       confirmed_qty = round(confirmed_qty)
 where unit <> 'kit'
    or requested_qty <> trunc(requested_qty) or approved_qty <> trunc(approved_qty)
    or donor_qty <> trunc(donor_qty) or confirmed_qty <> trunc(confirmed_qty);

update public.inventory_lots
   set unit = 'kit', quantity = round(quantity), reserved_qty = round(reserved_qty)
 where unit <> 'kit' or quantity <> trunc(quantity) or reserved_qty <> trunc(reserved_qty);

update public.inventory_reservations
   set quantity = greatest(1, round(quantity))
 where quantity <> trunc(quantity);

update public.inventory_movements
   set quantity = round(quantity)
 where quantity <> trunc(quantity);

-- 2. Defaults and table constraints.
alter table public.request_items   alter column unit set default 'kit';
alter table public.inventory_lots  alter column unit set default 'kit';

alter table public.request_items
  drop constraint if exists request_items_kit_check,
  add  constraint request_items_kit_check check (
    unit = 'kit'
    and requested_qty = trunc(requested_qty)
    and (approved_qty is null or approved_qty = trunc(approved_qty))
    and (donor_qty is null or donor_qty = trunc(donor_qty))
    and (confirmed_qty is null or confirmed_qty = trunc(confirmed_qty)));

alter table public.inventory_lots
  drop constraint if exists inventory_lots_kit_check,
  add  constraint inventory_lots_kit_check check (
    unit = 'kit' and quantity = trunc(quantity) and reserved_qty = trunc(reserved_qty));

-- 3. Trigger: any client unit ('unit', 'pcs', ...) becomes 'kit'; a fraction is refused with a clear code.
create or replace function public.fn_enforce_whole_kits()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.unit := 'kit';
  if tg_table_name = 'request_items' then
    if new.requested_qty <> trunc(new.requested_qty) or new.approved_qty <> trunc(new.approved_qty)
       or new.donor_qty <> trunc(new.donor_qty) or new.confirmed_qty <> trunc(new.confirmed_qty) then
      raise exception 'invalid_quantity';
    end if;
  else
    if new.quantity <> trunc(new.quantity) or new.reserved_qty <> trunc(new.reserved_qty) then
      raise exception 'invalid_quantity';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.fn_enforce_whole_kits() from public, anon, authenticated;

drop trigger if exists request_items_whole_kits on public.request_items;
create trigger request_items_whole_kits
  before insert or update on public.request_items
  for each row execute function public.fn_enforce_whole_kits();

drop trigger if exists inventory_lots_whole_kits on public.inventory_lots;
create trigger inventory_lots_whole_kits
  before insert or update on public.inventory_lots
  for each row execute function public.fn_enforce_whole_kits();