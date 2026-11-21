alter table profiles add column if not exists last_login_at timestamptz;

create table if not exists auth_attempts (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('login','reset','apply','upload')),
  identifier text not null,         
  ip text,
  success boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists auth_attempts_ident_idx on auth_attempts (kind, identifier, created_at desc);
create index if not exists auth_attempts_ip_idx    on auth_attempts (kind, ip, created_at desc);
alter table auth_attempts enable row level security;
revoke all on table auth_attempts from anon, authenticated;

create or replace function purge_auth_attempts() returns void
language sql security definer set search_path = public as $$
  delete from auth_attempts where created_at < now() - interval '2 days';
$$;
revoke execute on function purge_auth_attempts() from public, anon, authenticated;
grant execute on function purge_auth_attempts() to service_role;

create unique index if not exists volunteer_applications_live_email_uq
  on volunteer_applications (lower(email))
  where review_status in ('submitted','under_review','approved');

create unique index if not exists profiles_email_lower_uq on profiles (lower(email)) where email is not null;