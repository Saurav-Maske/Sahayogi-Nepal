-- Run in the SQL Editor of the DEMO project, after `supabase db push` (migration 20261122000009 reads these two vault entries).
-- Do not commit a copy with real values. Re-running is safe (existing entries are updated).
--
-- 1. push_function_url: the public URL of the send-push function.
-- 2. push_secret: the SAME value as PUSH_WEBHOOK_SECRET in supabase/functions/.env.demo.

-- Safe to run again: an entry that already exists is updated, a missing one is created.
do $$
declare
  v_url    text := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-push';
  v_secret text := '<PUSH_WEBHOOK_SECRET>';
begin
  if exists (select 1 from vault.secrets where name = 'push_function_url') then
    perform vault.update_secret((select id from vault.secrets where name = 'push_function_url'), v_url);
  else
    perform vault.create_secret(v_url, 'push_function_url');
  end if;
  if exists (select 1 from vault.secrets where name = 'push_secret') then
    perform vault.update_secret((select id from vault.secrets where name = 'push_secret'), v_secret);
  else
    perform vault.create_secret(v_secret, 'push_secret');
  end if;
end $$;

-- Check (names only, never print decrypted values in a screenshot):
select name from vault.secrets where name in ('push_function_url', 'push_secret') order by 1;   -- expect 2 rows

-- To replace a value:
--   select vault.update_secret((select id from vault.secrets where name = 'push_secret'), '<new value>');