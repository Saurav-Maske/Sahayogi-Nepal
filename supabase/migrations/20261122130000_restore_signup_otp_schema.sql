-- Restores what 20261122042602_remote_schema.sql removed but the Edge Functions still use.
-- Safe to run more than once.

-- 1. submit-volunteer-application inserts this column. Without it the insert fails
--    and the application never reaches the admin queue.
alter table public.volunteer_applications
  add column if not exists email_verified_at timestamptz;

-- 2. Throttle kinds used by the functions (ThrottleKind in _shared/auth.ts).
alter table public.auth_attempts drop constraint if exists auth_attempts_kind_check;
alter table public.auth_attempts
  add constraint auth_attempts_kind_check
  check (kind in ('login', 'reset', 'apply', 'upload', 'otp_send', 'otp_verify', 'status_check'));

-- 3. Called by reset-password after the new password is set.
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

-- 4. Housekeeping for email_otps.
create or replace function public.purge_email_otps()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.email_otps
   where greatest(expires_at, coalesce(token_expires_at, expires_at)) < now() - interval '1 day';
$$;

revoke all on function public.revoke_user_sessions(uuid) from public, anon, authenticated;
revoke all on function public.purge_email_otps()         from public, anon, authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;
grant execute on function public.purge_email_otps()         to service_role;

-- 5. Daily cleanup jobs (remote_schema.sql unscheduled them).
create extension if not exists pg_cron;

select cron.unschedule('purge-email-otps')
 where exists (select 1 from cron.job where jobname = 'purge-email-otps');
select cron.schedule('purge-email-otps', '23 3 * * *', $$select public.purge_email_otps();$$);

select cron.unschedule('purge-auth-attempts')
 where exists (select 1 from cron.job where jobname = 'purge-auth-attempts');
select cron.schedule('purge-auth-attempts', '29 3 * * *', $$select public.purge_auth_attempts();$$);