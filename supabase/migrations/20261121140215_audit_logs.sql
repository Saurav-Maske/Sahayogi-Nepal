-- Append-only, hash-chained audit log, written by Edge Functions (service role).
drop table if exists public.audit_logs cascade;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.audit_logs (
  id         bigint generated always as identity primary key,
  prev_hash  text not null,
  action     text not null,
  actor_id   uuid,                 -- no FK on purpose: deleting a user must not touch the log
  entity     text not null,
  entity_id  uuid,
  detail     jsonb,
  date       timestamptz not null default now(),
  hash_value text not null unique
);

-- One definition of the hash, shared by the trigger and the verifier.
create or replace function public.audit_row_hash(
  p_prev text, p_action text, p_actor uuid, p_entity text,
  p_entity_id uuid, p_detail jsonb, p_date timestamptz
) returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(digest(
    json_build_array(
      p_prev,
      coalesce(p_action, ''),
      coalesce(p_actor::text, ''),
      coalesce(p_entity, ''),
      coalesce(p_entity_id::text, ''),
      coalesce(p_detail::text, ''),
      to_char(p_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )::text,
    'sha256'), 'hex');
$$;

create or replace function public.fn_audit_logs_hash_chain()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
declare
  v_prev text;
begin
  perform pg_advisory_xact_lock(hashtext('public.audit_logs_hash_chain'));

  select l.hash_value into v_prev
    from public.audit_logs l
   order by l.id desc
   limit 1;

  v_prev := coalesce(v_prev, repeat('0', 64));

  new.date := coalesce(new.date, now());
  new.prev_hash := v_prev;  -- always overwrite whatever the caller sent
  new.hash_value := public.audit_row_hash(
    v_prev, new.action, new.actor_id, new.entity, new.entity_id, new.detail, new.date
  );
  return new;
end;
$$;

drop trigger if exists trg_audit_logs_hash_chain on public.audit_logs;
create trigger trg_audit_logs_hash_chain
before insert on public.audit_logs
for each row execute function public.fn_audit_logs_hash_chain();

create or replace function public.fn_audit_logs_append_only()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'audit_logs is append-only (% is forbidden)', tg_op;
end;
$$;

drop trigger if exists trg_audit_logs_append_only on public.audit_logs;
create trigger trg_audit_logs_append_only
before update or delete on public.audit_logs
for each row execute function public.fn_audit_logs_append_only();

drop trigger if exists trg_audit_logs_no_truncate on public.audit_logs;
create trigger trg_audit_logs_no_truncate
before truncate on public.audit_logs
for each statement execute function public.fn_audit_logs_append_only();

-- Access: only the service role (Edge Functions) may touch the table.
alter table public.audit_logs enable row level security;  -- no policies = no client access
revoke all on public.audit_logs from anon, authenticated;
revoke update, delete, truncate on public.audit_logs from service_role;

-- Preferred insert path for Edge Functions: takes the chain lock BEFORE the id is
-- assigned, so id order always equals chain order even under concurrent writes.
create or replace function public.append_audit_log(
  p_action text,
  p_actor_id uuid,
  p_entity text,
  p_entity_id uuid default null,
  p_detail jsonb default null
) returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('public.audit_logs_hash_chain'));

  insert into public.audit_logs (action, actor_id, entity, entity_id, detail)
  values (p_action, p_actor_id, p_entity, p_entity_id, p_detail)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.append_audit_log(text, uuid, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.append_audit_log(text, uuid, text, uuid, jsonb) to service_role;

-- Walks the chain in id order; returns the first broken row, or nothing if intact.
create or replace function public.verify_audit_chain()
returns table (broken_id bigint, reason text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record;
  v_prev text := repeat('0', 64);
begin
  for r in select * from public.audit_logs order by id loop
    if r.prev_hash is distinct from v_prev then
      broken_id := r.id; reason := 'prev_hash does not match previous row';
      return next; return;
    end if;
    if r.hash_value is distinct from public.audit_row_hash(
         r.prev_hash, r.action, r.actor_id, r.entity, r.entity_id, r.detail, r.date) then
      broken_id := r.id; reason := 'row contents do not match hash_value';
      return next; return;
    end if;
    v_prev := r.hash_value;
  end loop;
end;
$$;

revoke all on function public.verify_audit_chain() from public, anon, authenticated;
grant execute on function public.verify_audit_chain() to service_role;