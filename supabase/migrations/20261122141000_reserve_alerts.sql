-- Reserve alerts: when central inventory falls below a fixed reserve for a category, every phone that has the
-- app gets a push asking for donations of that item.
--
-- What "stock" means here: units still in the central inventory and not promised to an approved request,
-- i.e. sum(quantity - reserved_qty) over lots in phase received, processing or ready_to_ship. Donated stock
-- counts from pickup (lots are created as 'received' at pickup). Dispatched, consumed, returned and adjusted
-- lots do not count.
--
-- Flow: any change to inventory_lots runs _reserve_check(); a category that is below its reserve for the first
-- time queues ONE 'low_stock' row in push_outbox; send-push broadcasts it to every registered device. When stock
-- is back at or above the reserve the flag resets, so the next drop alerts again.
-- Safe to run more than once.

-- 1. Reserve levels (one row per category) ---------------------------------------------------------------------
create table if not exists public.inventory_reserve_levels (
  item_type     public.item_type primary key,
  min_qty       numeric(12,2) not null default 0 check (min_qty >= 0 and min_qty = trunc(min_qty)),  -- kits; 0 = no alert
  below_reserve boolean not null default false,   -- true while stock is under min_qty (alert already sent)
  last_alert_at timestamptz,
  updated_at    timestamptz not null default now()
);

alter table public.inventory_reserve_levels enable row level security;   -- no policies: functions only
revoke all on public.inventory_reserve_levels from public, anon, authenticated;

-- 2. Stock per category ----------------------------------------------------------------------------------------
create or replace function public._reserve_stock(p_item public.item_type)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(sum(l.quantity - l.reserved_qty), 0)
    from public.inventory_lots l
   where l.item_type = p_item
     and l.phase in ('received', 'processing', 'ready_to_ship');
$$;

-- 3. Starting values: 10 kits per category (PLACEHOLDER, the admin changes them with admin_set_reserve_level).
-- The starting state is set from today's stock without sending any alert.
insert into public.inventory_reserve_levels (item_type, min_qty)
select t, 10 from unnest(enum_range(null::public.item_type)) as t
on conflict (item_type) do nothing;

update public.inventory_reserve_levels r
   set below_reserve = (r.min_qty > 0 and public._reserve_stock(r.item_type) < r.min_qty);

-- 4. Push outbox: allow broadcast rows ---------------------------------------------------------------------------
alter table public.push_outbox
  alter column assignment_id   drop not null,
  alter column request_id      drop not null,
  alter column assignment_type drop not null;

alter table public.push_outbox add column if not exists item_type public.item_type;

do $$
declare c record;
begin
  for c in
    select con.conname from pg_constraint con
     where con.conrelid = 'public.push_outbox'::regclass and con.contype = 'c'
       and pg_get_constraintdef(con.oid) like '%new_offer%'
  loop
    execute format('alter table public.push_outbox drop constraint %I', c.conname);
  end loop;
end
$$;

alter table public.push_outbox
  drop constraint if exists push_outbox_kind_check,
  drop constraint if exists push_outbox_low_stock_chk,
  add constraint push_outbox_kind_check
    check (kind in ('new_offer', 'escalated', 'low_stock')),
  add constraint push_outbox_low_stock_chk
    check (kind <> 'low_stock' or item_type is not null);

-- push_claim_batch returns item_type too (return type changed, so the function is dropped and recreated).
drop function if exists public.push_claim_batch(int);

create or replace function public.push_claim_batch(p_limit int default 50)
returns table (
  id              bigint,
  kind            text,
  assignment_id   uuid,
  request_id      uuid,
  assignment_type text,
  attempts        int,
  item_type       text
)
language sql
security definer
set search_path = public
as $$
  with c as (
    select o.id
      from public.push_outbox o
     where o.processed_at is null
       and o.attempts < 5
       and (o.locked_at is null or o.locked_at < now() - interval '5 minutes')
     order by o.id
     limit greatest(1, least(coalesce(p_limit, 50), 200))
       for update skip locked
  )
  update public.push_outbox o
     set locked_at = now(), attempts = o.attempts + 1
    from c
   where o.id = c.id
  returning o.id, o.kind, o.assignment_id, o.request_id, o.assignment_type::text, o.attempts, o.item_type::text;
$$;

-- 5. Devices: normal users have no account, so a token may have no profile -----------------------------------
alter table public.device_tokens alter column profile_id drop not null;

-- Called by the app for everyone (logged in or not). Stores the token without a profile; if the token is
-- already stored (for example under a volunteer) the owner is left as it is and only last_seen_at moves.
create or replace function public.register_public_device_token(p_token text, p_platform text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text := btrim(coalesce(p_token, ''));
begin
  if char_length(v_token) not between 20 and 4096 or v_token ~ '\s' then raise exception 'invalid_token'; end if;
  if p_platform is null or p_platform not in ('android', 'ios', 'web') then raise exception 'invalid_platform'; end if;

  insert into public.device_tokens (profile_id, token, platform, last_seen_at)
  values (null, v_token, p_platform, now())
  on conflict (token) do update
    set platform = excluded.platform, last_seen_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

-- Everyone who should hear about a low-stock alert: every device seen in the last 90 days, one row per token.
create or replace function public.push_recipients_all()
returns table (token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (t.token) t.token, t.platform
    from public.device_tokens t
   where t.last_seen_at > now() - interval '90 days'
   order by t.token;
$$;

-- 6. The check -----------------------------------------------------------------------------------------------
-- Returns how many alerts were queued. Rows are locked in item_type order so parallel checks cannot deadlock.
create or replace function public._reserve_check()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r       record;
  v_stock numeric;
  v_n     int := 0;
begin
  for r in select * from public.inventory_reserve_levels order by item_type for update loop
    v_stock := public._reserve_stock(r.item_type);

    if r.min_qty > 0 and v_stock < r.min_qty then
      if not r.below_reserve then
        update public.inventory_reserve_levels
           set below_reserve = true, last_alert_at = now(), updated_at = now()
         where item_type = r.item_type;
        insert into public.push_outbox (kind, item_type) values ('low_stock', r.item_type);
        v_n := v_n + 1;
      end if;
    elsif r.below_reserve then
      update public.inventory_reserve_levels
         set below_reserve = false, updated_at = now()
       where item_type = r.item_type;
    end if;
  end loop;

  if v_n > 0 then perform public._push_kick(); end if;
  return v_n;
end;
$$;

-- Runs after every statement that changes inventory_lots. A problem here never breaks the business transaction.
create or replace function public._trg_reserve_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public._reserve_check();
  exception when others then
    raise warning '_reserve_check failed: %', sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists inventory_lots_reserve_check on public.inventory_lots;
create trigger inventory_lots_reserve_check
  after insert or update or delete on public.inventory_lots
  for each statement execute function public._trg_reserve_check();

-- 7. Admin RPCs ------------------------------------------------------------------------------------------------
-- admin_list_reserve_levels: one entry per category with the current stock, so the admin can see how close it is.
create or replace function public.admin_list_reserve_levels()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'item_type', r.item_type,
             'min_qty', r.min_qty,
             'stock', public._reserve_stock(r.item_type),
             'below_reserve', r.below_reserve,
             'last_alert_at', r.last_alert_at
           ) order by r.item_type)
      from public.inventory_reserve_levels r
  ), '[]'::jsonb);
end;
$$;

-- admin_set_reserve_level: p_min_qty is a whole number of kits; 0 switches the alert off for that category.
-- The check runs straight away, so lowering stock-vs-reserve takes effect (and alerts) immediately.
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
  on conflict (item_type) do update set min_qty = excluded.min_qty, updated_at = now();

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

-- 8. Privileges (see 20261122000011_function_privileges.sql: service_role only unless it is a client RPC) -------
revoke all on function public._reserve_stock(public.item_type)          from public, anon, authenticated;
revoke all on function public._reserve_check()                          from public, anon, authenticated;
revoke all on function public._trg_reserve_check()                      from public, anon, authenticated;
revoke all on function public.push_claim_batch(int)                     from public, anon, authenticated;
revoke all on function public.push_recipients_all()                     from public, anon, authenticated;
revoke all on function public.register_public_device_token(text, text)  from public, anon, authenticated;
revoke all on function public.admin_list_reserve_levels()               from public, anon, authenticated;
revoke all on function public.admin_set_reserve_level(text, numeric)    from public, anon, authenticated;

grant execute on function public._reserve_stock(public.item_type)       to service_role;
grant execute on function public._reserve_check()                       to service_role;
grant execute on function public.push_claim_batch(int)                  to service_role;
grant execute on function public.push_recipients_all()                  to service_role;

grant execute on function public.register_public_device_token(text, text) to anon, authenticated;
grant execute on function public.admin_list_reserve_levels()               to authenticated;
grant execute on function public.admin_set_reserve_level(text, numeric)    to authenticated;