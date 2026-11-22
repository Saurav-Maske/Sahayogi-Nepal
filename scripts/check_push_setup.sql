-- E5: read-only check of the one-time push setup. Run in the SQL Editor of a project after db push.
-- It prints names and counts only, never secret values. Every row should say ok.
select 'vault: push_function_url' as check_name,
       case when exists (select 1 from vault.secrets where name = 'push_function_url') then 'ok' else 'MISSING' end as result
union all
select 'vault: push_secret',
       case when exists (select 1 from vault.secrets where name = 'push_secret') then 'ok' else 'MISSING' end
union all
select 'extension: pg_net',  case when exists (select 1 from pg_extension where extname = 'pg_net')  then 'ok' else 'MISSING' end
union all
select 'extension: pg_cron', case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'ok' else 'MISSING' end
union all
select 'cron job: ' || j, case when exists (select 1 from cron.job where jobname = j) then 'ok' else 'MISSING' end
  from unnest(array['push-escalations', 'purge-push-outbox']) as j
union all
select 'registered devices (last 90 days)', count(*)::text from public.device_tokens where last_seen_at > now() - interval '90 days'
union all
select 'outbox rows waiting', count(*)::text from public.push_outbox where processed_at is null
union all
select 'outbox rows that failed 5 times', count(*)::text from public.push_outbox where processed_at is null and attempts >= 5;

-- Also needed, and not visible from SQL: Edge Function secrets FCM_SERVICE_ACCOUNT and PUSH_WEBHOOK_SECRET
-- (same value as the vault push_secret), and send-push deployed. Check with: supabase secrets list