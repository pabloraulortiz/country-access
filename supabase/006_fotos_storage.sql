-- Fotos de perfil (guardias y demás usuarios). Bucket privado: la app usa URLs firmadas.
-- Ruta del archivo: <country_id>/<profile_id>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos'
         and public.current_role_name() in ('admin', 'guard')
         and (storage.foldername(name))[1] = public.current_country()::text);

create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-photos'
              and public.current_role_name() = 'admin'
              and (storage.foldername(name))[1] = public.current_country()::text);

create policy photos_update on storage.objects for update to authenticated
  using (bucket_id = 'profile-photos'
         and public.current_role_name() = 'admin'
         and (storage.foldername(name))[1] = public.current_country()::text)
  with check (bucket_id = 'profile-photos'
              and public.current_role_name() = 'admin'
              and (storage.foldername(name))[1] = public.current_country()::text);

create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos'
         and public.current_role_name() = 'admin'
         and (storage.foldername(name))[1] = public.current_country()::text);
