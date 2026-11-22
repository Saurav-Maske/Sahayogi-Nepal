-- Push notification outbox (FCM), drained by the send-push Edge Function.
--
-- RECONSTRUCTED from supabase/functions/send-push/index.ts, _shared/fcm.ts, docs/CHANGELOG.md and
-- docs/API-CONTRACT.md ("Push notifications"), because the original file was empty (0 bytes) in
-- Sahayogi-Nepal-test.zip. If the original exists in Git on a project that already ran it, keep that one.
-- Safe to run more than once.
--
-- Flow: a trigger queues a row -> _push_kick() calls send-push through pg_net -> send-push calls
-- push_claim_batch(), push_recipients() and FCM -> marks the rows processed. pg_cron re-kicks every minute
-- (retries, escalations). Payloads are IDs only; the OTP is never pushed.
--
-- ONE-TIME SETUP PER PROJECT (not in a migration because the values are secrets / project specific):
--   select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/send-push', 'push_function_url');
--   select vault.create_secret('<same value as the PUSH_WEBHOOK_SECRET function secret>', 'push_secret');
--   (local: http://host.docker.internal:54321/functions/v1/send-push)
-- Without both vault entries nothing is sent and the outbox just waits.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- 1. Outbox -------------------------------------------------------------------------------------------
create table if not exists public.push_outbox (
  id              bigint generated always as identity primary key,
  kind            text not null check (kind in ('new_offer', 'escalated')),
  assignment_id   uuid not null references public.assignments(id) on delete cascade,
  request_id      uuid not null references public.requests(id) on delete cascade,
  assignment_type assignment_type not null,
  attempts        int not null default 0,        -- incremented every time a batch claims the row (max 5)
  locked_at       timestamptz,                   -- set while a send-push run holds the row
  processed_at    timestamptz,                   -- set when done (sent, or nobody left to tell)
  last_error      text,
  created_at      timestamptz not null default now()
);

create index if not exists push_outbox_pending_idx on public.push_outbox (id) where processed_at is null;
-- An escalation is queued once per assignment, however often the cron job runs.
create unique index if not exists push_outbox_escalated_once_uq
  on public.push_outbox (assignment_id) where kind = 'escalated';

alter table public.push_outbox enable row level security;   -- no policies: service role only
revoke all on table public.push_outbox from public, anon, authenticated;
grant all on table public.push_outbox to service_role;

-- 2. Wake the sender ----------------------------------------------------------------------------------
-- pg_net sends the request after the surrounding transaction commits, so the rows are visible to send-push.
-- Never lets a push problem break the business transaction.
create or replace function public._push_kick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url    from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_secret';
  if v_url is null or v_secret is null then return; end if;

  perform net.http_post(
    url                  := v_url,
    headers              := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body                 := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  raise warning '_push_kick failed: %', sqlerrm;
end;
$$;

-- 3. Triggers: queue a new_offer row ------------------------------------------------------------------
-- Statement level with transition tables, so a manpower request that creates 20 assignments queues 20 rows
-- and kicks the sender once.
-- (a) an assignment is inserted as an open offer
create or replace function public._push_enqueue_offers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.push_outbox (kind, assignment_id, request_id, assignment_type)
  select 'new_offer', n.id, n.request_id, n.assignment_type
    from new_rows n
   where n.state = 'offered' and n.volunteer_id is null;
  if found then perform public._push_kick(); end if;
  return null;
end;
$$;

-- (b) a volunteer releases an accepted assignment back to the pool (decline_assignment, released: true)
create or replace function public._push_enqueue_released()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.push_outbox (kind, assignment_id, request_id, assignment_type)
  select 'new_offer', n.id, n.request_id, n.assignment_type
    from new_rows n
    join old_rows o on o.id = n.id
   where o.volunteer_id is not null
     and n.volunteer_id is null
     and n.state = 'offered';
  if found then perform public._push_kick(); end if;
  return null;
end;
$$;

drop trigger if exists push_new_offer_ins on public.assignments;
create trigger push_new_offer_ins
  after insert on public.assignments
  referencing new table as new_rows
  for each statement execute function public._push_enqueue_offers();

drop trigger if exists push_new_offer_released on public.assignments;
create trigger push_new_offer_released
  after update on public.assignments
  referencing old table as old_rows new table as new_rows
  for each statement execute function public._push_enqueue_released();

-- 4. Escalation: tier A offers nobody took within 60 s ---------------------------------------------------
-- Until escalate_at only volunteers with exactly {A} see the offer; afterwards everyone holding A does.
-- Queues one 'escalated' row per assignment; push_recipients() picks the newly eligible volunteers.
create or replace function public._push_enqueue_escalations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  insert into public.push_outbox (kind, assignment_id, request_id, assignment_type)
  select 'escalated', a.id, a.request_id, a.assignment_type
    from public.assignments a
    join public.requests r on r.id = a.request_id
   where a.required_tier = 'A'
     and a.state = 'offered'
     and a.volunteer_id is null
     and a.escalate_at is not null
     and a.escalate_at <= now()
     and r.status = 'awaiting_assignment'
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Cron tick (every minute): queue escalations, free rows whose sender died, wake the sender if work is waiting.
create or replace function public._push_tick()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._push_enqueue_escalations();

  update public.push_outbox
     set locked_at = null
   where processed_at is null and locked_at < now() - interval '5 minutes';

  if exists (select 1 from public.push_outbox
              where processed_at is null and locked_at is null and attempts < 5) then
    perform public._push_kick();
  end if;
end;
$$;

-- 5. Used by send-push ------------------------------------------------------------------------------------
-- Takes up to p_limit unfinished rows (oldest first), marks them locked and counts the attempt.
-- SKIP LOCKED lets two parallel send-push runs work on different rows. A row is tried at most 5 times.
create or replace function public.push_claim_batch(p_limit int default 50)
returns table (
  id              bigint,
  kind            text,
  assignment_id   uuid,
  request_id      uuid,
  assignment_type text,
  attempts        int
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
  returning o.id, o.kind, o.assignment_id, o.request_id, o.assignment_type::text, o.attempts;
$$;

-- Who to tell, using the same rule as my_offers(): active volunteers who can see the offer right now, have not
-- declined it and hold no live assignment on the same request. Returns nothing once the offer is claimed
-- or the request left awaiting_assignment, so a late push is never sent for a taken offer.
--   new_offer : _tier_open_to() at this moment (tier A -> exactly {A} before escalate_at, then everyone with A)
--   escalated : tier A only, volunteers holding A plus B or C (the ones who could not see it before)
create or replace function public.push_recipients(p_assignment uuid, p_kind text)
returns table (profile_id uuid, token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, t.token, t.platform
    from public.assignments a
    join public.requests r      on r.id = a.request_id
    join public.profiles p      on p.role = 'volunteer' and p.account_status = 'active'
    join public.device_tokens t on t.profile_id = p.id
   where a.id = p_assignment
     and a.state = 'offered'
     and a.volunteer_id is null
     and r.status = 'awaiting_assignment'
     and not (p.id = any (a.declined_by))
     and not exists (
           select 1 from public.assignments b
            where b.request_id = a.request_id
              and b.volunteer_id = p.id
              and b.state not in ('declined', 'expired', 'cancelled'))
     and case p_kind
           when 'new_offer' then public._tier_open_to(a.required_tier, p.categories, a.escalate_at)
           when 'escalated' then a.required_tier = 'A'
                                 and p.categories @> array['A']::text[]
                                 and not (p.categories <@ array['A']::text[])
           else false
         end;
$$;

-- 6. Housekeeping job and schedule ------------------------------------------------------------------------
create or replace function public._push_purge()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_outbox
   where coalesce(processed_at, created_at) < now() - interval '7 days';
$$;

select cron.unschedule('push-escalations')
 where exists (select 1 from cron.job where jobname = 'push-escalations');
select cron.schedule('push-escalations', '* * * * *', $$select public._push_tick();$$);

select cron.unschedule('purge-push-outbox')
 where exists (select 1 from cron.job where jobname = 'purge-push-outbox');
select cron.schedule('purge-push-outbox', '17 3 * * *', $$select public._push_purge();$$);

-- 7. Privileges: service role only -------------------------------------------------------------------------
-- (Migration 20261122000011 sweeps this again and fails if anon or authenticated can run any of it.)
revoke all on function public._push_kick()                     from public, anon, authenticated;
revoke all on function public._push_enqueue_offers()           from public, anon, authenticated;
revoke all on function public._push_enqueue_released()         from public, anon, authenticated;
revoke all on function public._push_enqueue_escalations()      from public, anon, authenticated;
revoke all on function public._push_tick()                     from public, anon, authenticated;
revoke all on function public._push_purge()                    from public, anon, authenticated;
revoke all on function public.push_claim_batch(int)            from public, anon, authenticated;
revoke all on function public.push_recipients(uuid, text)      from public, anon, authenticated;

grant execute on function public._push_kick()                  to service_role;
grant execute on function public._push_enqueue_escalations()   to service_role;
grant execute on function public._push_tick()                  to service_role;
grant execute on function public._push_purge()                 to service_role;
grant execute on function public.push_claim_batch(int)         to service_role;
grant execute on function public.push_recipients(uuid, text)   to service_role;