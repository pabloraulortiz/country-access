-- ABM desde la app: email en profiles y permiso del admin para editar la configuración del country.
alter table profiles add column if not exists email text;

create policy countries_admin_update on countries for update
  using (id = current_country() and current_role_name() = 'admin')
  with check (id = current_country() and current_role_name() = 'admin');
