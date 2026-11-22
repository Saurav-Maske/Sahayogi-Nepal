-- Email OTP codes and proof tokens for signup and password reset.
-- Used by the shared OTP helpers (issueOtp / verifyOtp / claimToken / releaseToken).
-- One live row per (email, purpose): issuing a new code replaces the previous one.

create table if not exists public.email_otps (
  id               uuid primary key default gen_random_uuid(),
  email            text not null check (email = lower(email)),
  purpose          text not null check (purpose in ('signup', 'reset')),

  -- the 6-digit code (stored only as an HMAC hash)
  code_hash        text not null,
  sent_at          timestamptz not null default now(),
  expires_at       timestamptz not null,
  attempts         integer not null default 0 check (attempts >= 0),

  -- set once the code is verified; the proof token is stored only as an HMAC hash
  verified_at      timestamptz,
  token_hash       text,
  token_expires_at timestamptz,
  used_at          timestamptz,

  ip               text,

  -- required by the upsert: onConflict: "email,purpose"
  constraint email_otps_email_purpose_key unique (email, purpose)
);

-- Helps a periodic cleanup of expired rows.
create index if not exists email_otps_expires_at_idx on public.email_otps (expires_at);

-- Lock the table down: RLS on, no policies, no grants for client roles.
-- Only the service-role key (edge functions) can read or write it.
alter table public.email_otps enable row level security;
revoke all on table public.email_otps from anon, authenticated;

-- Optional: delete stale rows hourly (needs the pg_cron extension enabled).
-- select cron.schedule(
--   'email-otps-cleanup',
--   '0 * * * *',
--   $$ delete from public.email_otps
--      where expires_at < now() - interval '1 day'
--        and (token_expires_at is null or token_expires_at < now() - interval '1 day') $$
-- );