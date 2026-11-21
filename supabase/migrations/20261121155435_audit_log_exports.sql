create extension if not exists pg_cron;

create table if not exists public.audit_hash_checkpoints (
  id bigint generated always as identity primary key,
  audit_log_id bigint not null,
  hash_value text not null,
  audit_date timestamptz not null,
  exported_at timestamptz not null default now()
);

create or replace function public.fn_export_latest_audit_hash()
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_checkpoint_id bigint;
begin
  insert into public.audit_hash_checkpoints (
    audit_log_id,
    hash_value,
    audit_date
  )
  select
    l.id,
    l.hash_value,
    l.date
  from public.audit_logs l
  order by l.id desc
  limit 1
  returning id into v_checkpoint_id;

  return v_checkpoint_id;
end;
$$;

-- Unschedule first if updating an existing job with the same name
select cron.unschedule('export-latest-audit-hash')
where exists (
  select 1 from cron.job where jobname = 'export-latest-audit-hash'
);

-- Run every 2 hours on the hour (00:00, 02:00, 04:00... UTC)
select cron.schedule(
  'export-latest-audit-hash',
  '0 */2 * * *',
  $$select public.fn_export_latest_audit_hash();$$
);