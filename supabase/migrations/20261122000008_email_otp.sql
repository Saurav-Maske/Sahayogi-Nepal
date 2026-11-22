-- Email OTP for volunteer sign-up and forgot password.
--
-- RECONSTRUCTED from the code that uses it (supabase/functions/_shared/otp.ts, send-signup-otp,
-- verify-signup-otp, request-password-reset, verify-reset-otp, reset-password, submit-volunteer-application)
-- and from docs/CHANGELOG.md, because the original file was empty (0 bytes) in Sahayogi-Nepal-test.zip.
-- If the original exists in Git on a project that already ran it, keep that one and drop this file.
-- Safe to run more than once.

-- 1. One live code per email + purpose. Only HMAC hashes are stored, never the code or the proof token.
create table if not exists public.email_otps (
  id               uuid primary key default gen_random_uuid(),
  email            text not null,                         -- lower-cased by the functions
  purpose          text not null check (purpose in ('signup', 'reset')),
  code_hash        text not null,                         -- HMAC of the 6-digit code
  sent_at          timestamptz not null default now(),    -- drives the 60 s resend cooldown
  expires_at       timestamptz not null,                  -- code lifetime (10 min)
  attempts         int not null default 0 check (attempts >= 0),   -- guesses used, max 5
  verified_at      timestamptz,                           -- set when the right code was entered
  token_hash       text,                                  -- HMAC of the proof token handed to the client
  token_expires_at timestamptz,                           -- signup 30 min, reset 10 min
  used_at          timestamptz,                           -- proof token spent (single use)
  ip               text,
  unique (email, purpose)                                 -- upsert target: onConflict "email,purpose"
);

alter table public.email_otps enable row level security;   -- no policies: service role only
revoke all on table public.email_otps from public, anon, authenticated;
grant all on table public.email_otps to service_role;

-- 2. The throttle table gets two new kinds: otp_send (codes requested) and otp_verify (codes checked).
do $$
declare
  c record;
begin
  for c in
    select con.conname
      from pg_constraint con
     where con.conrelid = 'public.auth_attempts'::regclass
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%kind%'
  loop
    execute format('alter table public.auth_attempts drop constraint %I', c.conname);
  end loop;
end
$$;

alter table public.auth_attempts
  add constraint auth_attempts_kind_check
  check (kind in ('login', 'reset', 'apply', 'upload', 'otp_send', 'otp_verify'));

-- 3. Proof that the applicant owns the email address (set by submit-volunteer-application).
alter table public.volunteer_applications add column if not exists email_verified_at timestamptz;

-- 4. Housekeeping: drop rows whose code and proof token are both long expired.
create or replace function public.purge_email_otps()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.email_otps
   where greatest(expires_at, coalesce(token_expires_at, expires_at)) < now() - interval '1 day';
$$;

-- 5. Sign out a user everywhere (called by reset-password after the new password is set).
create or replace function public.revoke_user_sessions(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then return; end if;
  delete from auth.sessions       where user_id = p_user_id;
  delete from auth.refresh_tokens where user_id::text = p_user_id::text;
end;
$$;

-- 6. Service role only (the Edge Functions call these; no client may).
revoke all on function public.purge_email_otps()           from public, anon, authenticated;
revoke all on function public.revoke_user_sessions(uuid)   from public, anon, authenticated;
grant execute on function public.purge_email_otps()         to service_role;
grant execute on function public.revoke_user_sessions(uuid) to service_role;

-- 7. Daily housekeeping schedule (pg_cron, runs as postgres) -------------------------------------------
-- purge_email_otps() is defined above; purge_auth_attempts() comes from 20261121000003_auth_support.sql.
-- Neither was scheduled before. Re-running this migration replaces the jobs instead of duplicating them.
create extension if not exists pg_cron;

select cron.unschedule('purge-email-otps')
 where exists (select 1 from cron.job where jobname = 'purge-email-otps');
select cron.schedule('purge-email-otps', '23 3 * * *', $$select public.purge_email_otps();$$);

select cron.unschedule('purge-auth-attempts')
 where exists (select 1 from cron.job where jobname = 'purge-auth-attempts');
select cron.schedule('purge-auth-attempts', '29 3 * * *', $$select public.purge_auth_attempts();$$);