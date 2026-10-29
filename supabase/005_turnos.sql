-- Turnos de guardia: Día 07-19 (2), Noche 19-07 (2), Rondín 22-06 (1).
-- shift_date = fecha en que COMIENZA el turno (la Noche del 28 termina el 29 a las 07:00).

alter table profiles add column if not exists photo_path text;   -- foto de perfil (ver 006_fotos_storage.sql)

create table if not exists shifts (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  code text not null,
  name text not null,
  start_time time not null,
  end_time time not null,
  required_guards int not null default 1,
  unique (country_id, code)
);

create table if not exists shift_assignments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references shifts(id) on delete cascade,
  shift_date date not null,
  guard_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (shift_id, shift_date, guard_id)
);
create index if not exists shift_assignments_date_idx on shift_assignments(shift_date);

create or replace function seed_shifts(p_country uuid) returns void
language sql security definer set search_path = public as
$$
  insert into shifts(country_id, code, name, start_time, end_time, required_guards) values
    (p_country, 'day',    'Día',    '07:00', '19:00', 2),
    (p_country, 'night',  'Noche',  '19:00', '07:00', 2),
    (p_country, 'rondin', 'Rondín', '22:00', '06:00', 1)
  on conflict (country_id, code) do nothing
$$;

select seed_shifts(id) from countries;

create or replace function trg_seed_shifts() returns trigger
language plpgsql security definer set search_path = public as
$$ begin perform seed_shifts(new.id); return new; end $$;
drop trigger if exists countries_seed_shifts on countries;
create trigger countries_seed_shifts after insert on countries for each row execute function trg_seed_shifts();

-- Solo se puede asignar a usuarios con rol guardia del mismo country
create or replace function trg_check_assignment() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if not exists (
    select 1 from profiles p join shifts s on s.id = new.shift_id
    where p.id = new.guard_id and p.role = 'guard' and p.country_id = s.country_id) then
    raise exception 'El usuario no es guardia de este country';
  end if;
  return new;
end $$;
drop trigger if exists shift_assignments_check on shift_assignments;
create trigger shift_assignments_check before insert or update on shift_assignments
  for each row execute function trg_check_assignment();

alter table shifts enable row level security;
alter table shift_assignments enable row level security;

create policy shifts_read on shifts for select
  using (country_id = current_country() and current_role_name() in ('admin','guard'));
create policy shifts_admin on shifts for all
  using (country_id = current_country() and current_role_name() = 'admin')
  with check (country_id = current_country() and current_role_name() = 'admin');

create policy sa_read on shift_assignments for select
  using (current_role_name() in ('admin','guard')
         and exists (select 1 from shifts s where s.id = shift_id and s.country_id = current_country()));
create policy sa_admin on shift_assignments for all
  using (current_role_name() = 'admin'
         and exists (select 1 from shifts s where s.id = shift_id and s.country_id = current_country()))
  with check (current_role_name() = 'admin'
         and exists (select 1 from shifts s where s.id = shift_id and s.country_id = current_country()));

-- Turnos activos ahora, con los guardias asignados y si el usuario actual está en ellos
create or replace function current_shift_info() returns jsonb
language plpgsql stable security definer set search_path = public as
$$
declare
  nowl timestamp := now() at time zone 'America/Argentina/Cordoba';
  t time := nowl::time;
  d date := nowl::date;
  res jsonb;
begin
  if current_role_name() not in ('admin','guard') then raise exception 'No autorizado'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'code', s.code, 'name', s.name,
      'start', to_char(s.start_time, 'HH24:MI'), 'end', to_char(s.end_time, 'HH24:MI'),
      'required', s.required_guards,
      'guards', (select coalesce(jsonb_agg(jsonb_build_object('name', p.full_name, 'photo', p.photo_path) order by p.full_name), '[]'::jsonb)
                 from shift_assignments a join profiles p on p.id = a.guard_id
                 where a.shift_id = s.id and a.shift_date = x.sd),
      'mine', exists (select 1 from shift_assignments a
                      where a.shift_id = s.id and a.shift_date = x.sd and a.guard_id = auth.uid())
    ) order by s.start_time), '[]'::jsonb)
  into res
  from shifts s
  cross join lateral (select case when s.start_time < s.end_time or t >= s.start_time then d else d - 1 end as sd) x
  where s.country_id = current_country()
    and ((s.start_time < s.end_time and t >= s.start_time and t < s.end_time)
      or (s.start_time > s.end_time and (t >= s.start_time or t < s.end_time)));

  return res;
end $$;
