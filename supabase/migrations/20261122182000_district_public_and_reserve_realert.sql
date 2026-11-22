-- E4: apps cannot read app_settings directly any more (policy settings_public_read was dropped).
-- Serve the 'district' map config through a read-only function instead of opening the table again.
create or replace function public.get_district_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select value from public.app_settings where key = 'district';
$$;

revoke all on function public.get_district_config() from public, anon, authenticated;
grant execute on function public.get_district_config() to anon, authenticated;

-- E7: the low-stock alert only fired on a drop. Now, when an admin CHANGES a reserve level, the flag is reset
-- first, so a category that is already below its new reserve alerts once, straight away.
-- Setting the same value again does not re-alert.
create or replace function public.admin_set_reserve_level(p_item_type text, p_min_qty numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_type  public.item_type;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  begin
    v_type := p_item_type::public.item_type;
  exception when invalid_text_representation then
    raise exception 'invalid_items';
  end;
  if v_type is null then raise exception 'invalid_items'; end if;

  if p_min_qty is null or p_min_qty < 0 or p_min_qty > 1000000 or p_min_qty <> trunc(p_min_qty) then
    raise exception 'invalid_qty';
  end if;

  insert into public.inventory_reserve_levels (item_type, min_qty)
  values (v_type, p_min_qty)
  on conflict (item_type) do update
    set min_qty       = excluded.min_qty,
        below_reserve = case when public.inventory_reserve_levels.min_qty is distinct from excluded.min_qty
                             then false else public.inventory_reserve_levels.below_reserve end,
        updated_at    = now();

  perform public.append_audit_log(
    'reserve_level_set', v_admin, 'inventory', null,
    jsonb_build_object('item_type', v_type, 'min_qty', p_min_qty)
  );

  perform public._reserve_check();

  return (
    select jsonb_build_object(
             'item_type', r.item_type, 'min_qty', r.min_qty,
             'stock', public._reserve_stock(r.item_type),
             'below_reserve', r.below_reserve, 'last_alert_at', r.last_alert_at)
      from public.inventory_reserve_levels r where r.item_type = v_type
  );
end;
$$;

revoke all on function public.admin_set_reserve_level(text, numeric) from public, anon, authenticated;
grant execute on function public.admin_set_reserve_level(text, numeric) to authenticated;