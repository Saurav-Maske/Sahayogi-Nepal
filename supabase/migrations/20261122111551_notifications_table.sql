-- In-app notifications, one row per message per user.
-- Created by edge functions (service role); users can only read their own.

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  type       text not null default 'general',        -- e.g. 'application_status', 'assignment', 'general'
  title      text,
  body       text not null,
  data       jsonb not null default '{}'::jsonb,     -- extra payload, e.g. {"application_id": "..."}
  created_at timestamptz not null default now()
);

-- Inbox list, newest first.
create index if not exists notifications_profile_created_idx
  on public.notifications (profile_id, created_at desc);

alter table public.notifications enable row level security;

-- Clients can only read. Inserts, updates and deletes come from edge functions (service role).
revoke all on table public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;

-- NOTE: this policy assumes profiles.id is the same as the signed-in user's auth id (auth.uid()).
-- If your profiles table uses a separate column for the auth id, change the comparison below.
drop policy if exists "read own notifications" on public.notifications;
create policy "read own notifications" on public.notifications
  for select to authenticated
  using (profile_id = auth.uid());

-- Optional: let the app receive new notifications live (Supabase Realtime).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;