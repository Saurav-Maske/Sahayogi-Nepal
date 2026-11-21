insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('volunteer-docs', 'volunteer-docs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists docs_admin_read on storage.objects;
create policy docs_admin_read on storage.objects for select
  using (bucket_id = 'volunteer-docs' and public.is_admin());