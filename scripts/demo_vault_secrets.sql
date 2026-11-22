-- Run ONCE in the SQL Editor of the DEMO project, after `supabase db push` (migration 20261122000009 reads these two vault entries).
-- Do not commit a copy with real values. Re-running: delete the old entries first (see the bottom), vault names are unique.
--
-- 1. push_function_url: the public URL of the send-push function.
-- 2. push_secret: the SAME value as PUSH_WEBHOOK_SECRET in supabase/functions/.env.demo.

select vault.create_secret('https://<PROJECT_REF>.supabase.co/functions/v1/send-push', 'push_function_url');
select vault.create_secret('<PUSH_WEBHOOK_SECRET>', 'push_secret');

-- Check (names only, never print decrypted values in a screenshot):
select name from vault.secrets where name in ('push_function_url', 'push_secret') order by 1;   -- expect 2 rows

-- To replace a value:
--   select vault.update_secret((select id from vault.secrets where name = 'push_secret'), '<new value>');