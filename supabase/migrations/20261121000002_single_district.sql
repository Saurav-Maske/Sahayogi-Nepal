alter table requests alter column district_id drop not null;

drop policy if exists settings_read on app_settings;
drop policy if exists settings_public_read on app_settings;
create policy settings_public_read on app_settings for select using (key = 'district');