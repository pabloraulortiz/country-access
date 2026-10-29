-- Control de acceso para country (Supabase / PostgreSQL)
-- Ejecutar en SQL Editor de Supabase.

create extension if not exists pgcrypto;

-- ============ ENUMS ============
create type user_role as enum ('admin', 'guard', 'owner');
create type visit_type as enum ('single', 'range', 'recurring', 'service');
create type visit_status as enum ('pending', 'authorized', 'rejected', 'cancelled', 'expired');
create type access_direction as enum ('in', 'out');
create type access_result as enum ('allowed', 'denied');

-- ============ TABLAS ============
create table countries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table lots (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  code text not null,                 -- Ej: "Mz 12 Lote 5"
  active boolean not null default true,
  unique (country_id, code)
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  country_id uuid not null references countries(id),
  role user_role not null default 'owner',
  full_name text not null,
  dni text,
  phone text,
  fcm_token text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Un propietario puede tener varios lotes y un lote varios propietarios
create table lot_owners (
  lot_id uuid not null references lots(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  primary key (lot_id, profile_id)
);

create table visitors (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  full_name text not null,
  dni text,
  plate text,
  is_frequent boolean not null default false,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index on visitors (country_id, dni);
create index on visitors (country_id, plate);

create table visits (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  lot_id uuid not null references lots(id),
  visitor_id uuid not null references visitors(id),
  created_by uuid not null references profiles(id),
  type visit_type not null default 'single',
  status visit_status not null default 'authorized',
  valid_from timestamptz not null default now(),
  valid_to timestamptz not null,
  max_uses int not null default 1,
  uses int not null default 0,
  -- recurrente: días de semana 1..7 (lunes=1) y franja horaria
  weekdays int[],
  time_from time,
  time_to time,
  qr_token text not null unique default encode(gen_random_bytes(24), 'hex'),
  notes text,
  created_at timestamptz not null default now()
);
create index on visits (lot_id, status);
create index on visits (qr_token);

create table access_logs (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  lot_id uuid references lots(id),
  visit_id uuid references visits(id),
  visitor_id uuid references visitors(id),
  guard_id uuid not null references profiles(id),
  direction access_direction not null,
  result access_result not null,
  reason text,
  plate text,
  dni text,
  created_at timestamptz not null default now()
);
create index on access_logs (country_id, created_at desc);

-- Solicitudes en vivo: visita sin autorización previa, la guardia pide aprobación
create table live_requests (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  lot_id uuid not null references lots(id),
  guard_id uuid not null references profiles(id),
  visitor_name text not null,
  dni text,
  plate text,
  status visit_status not null default 'pending',
  responded_by uuid references profiles(id),
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index on live_requests (lot_id, status);

create table blocklist (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  dni text,
  plate text,
  reason text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  check (dni is not null or plate is not null)
);

create table panic_events (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  guard_id uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

-- ============ HELPERS DE SEGURIDAD ============
create or replace function current_role_name() returns user_role
language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() and active $$;

create or replace function current_country() returns uuid
language sql stable security definer set search_path = public as
$$ select country_id from profiles where id = auth.uid() and active $$;

create or replace function owns_lot(p_lot uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from lot_owners where lot_id = p_lot and profile_id = auth.uid()) $$;

-- ============ RLS ============
alter table countries enable row level security;
alter table lots enable row level security;
alter table profiles enable row level security;
alter table lot_owners enable row level security;
alter table visitors enable row level security;
alter table visits enable row level security;
alter table access_logs enable row level security;
alter table live_requests enable row level security;
alter table blocklist enable row level security;
alter table panic_events enable row level security;

create policy countries_read on countries for select using (id = current_country());

create policy lots_read on lots for select using (country_id = current_country());
create policy lots_admin on lots for all
  using (country_id = current_country() and current_role_name() = 'admin')
  with check (country_id = current_country() and current_role_name() = 'admin');

create policy profiles_read on profiles for select
  using (id = auth.uid() or (country_id = current_country() and current_role_name() in ('admin','guard')));
create policy profiles_self_update on profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = current_role_name());
create policy profiles_admin on profiles for all
  using (country_id = current_country() and current_role_name() = 'admin')
  with check (country_id = current_country() and current_role_name() = 'admin');

create policy lot_owners_read on lot_owners for select
  using (profile_id = auth.uid() or current_role_name() in ('admin','guard'));
create policy lot_owners_admin on lot_owners for all
  using (current_role_name() = 'admin') with check (current_role_name() = 'admin');

create policy visitors_read on visitors for select using (country_id = current_country());
create policy visitors_insert on visitors for insert
  with check (country_id = current_country() and current_role_name() in ('admin','owner','guard'));
create policy visitors_update on visitors for update
  using (country_id = current_country() and (created_by = auth.uid() or current_role_name() = 'admin'));

create policy visits_read on visits for select
  using (country_id = current_country() and (current_role_name() in ('admin','guard') or owns_lot(lot_id)));
create policy visits_owner_insert on visits for insert
  with check (country_id = current_country() and created_by = auth.uid() and owns_lot(lot_id));
create policy visits_owner_update on visits for update
  using (country_id = current_country() and (owns_lot(lot_id) or current_role_name() = 'admin'));

create policy logs_read on access_logs for select
  using (country_id = current_country() and (current_role_name() in ('admin','guard') or owns_lot(lot_id)));
-- los logs solo se insertan vía funciones security definer

create policy live_read on live_requests for select
  using (country_id = current_country() and (current_role_name() in ('admin','guard') or owns_lot(lot_id)));
create policy live_guard_insert on live_requests for insert
  with check (country_id = current_country() and guard_id = auth.uid() and current_role_name() = 'guard');
create policy live_owner_update on live_requests for update
  using (country_id = current_country() and owns_lot(lot_id))
  with check (owns_lot(lot_id));

create policy block_read on blocklist for select
  using (country_id = current_country() and current_role_name() in ('admin','guard'));
create policy block_admin on blocklist for all
  using (country_id = current_country() and current_role_name() = 'admin')
  with check (country_id = current_country() and current_role_name() = 'admin');

create policy panic_read on panic_events for select
  using (country_id = current_country() and current_role_name() in ('admin','guard'));
create policy panic_insert on panic_events for insert
  with check (country_id = current_country() and guard_id = auth.uid() and current_role_name() = 'guard');

-- ============ FUNCIONES ============

-- Valida un QR y registra el ingreso/egreso. Solo guardias.
create or replace function validate_qr(p_token text, p_direction access_direction default 'in')
returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  v visits%rowtype;
  vis visitors%rowtype;
  lot_code text;
  g profiles%rowtype;
  reason text := null;
  now_local timestamp := (now() at time zone 'America/Argentina/Cordoba');
  dow int := extract(isodow from now_local)::int;
begin
  select * into g from profiles where id = auth.uid() and active and role in ('guard','admin');
  if not found then raise exception 'No autorizado'; end if;

  select * into v from visits where qr_token = p_token and country_id = g.country_id;
  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'QR inválido');
  end if;

  select * into vis from visitors where id = v.visitor_id;
  select code into lot_code from lots where id = v.lot_id;

  if v.status <> 'authorized' then reason := 'Visita ' || v.status;
  elsif now() < v.valid_from then reason := 'Aún no es válida';
  elsif now() > v.valid_to then reason := 'Vencida';
  elsif p_direction = 'in' and v.uses >= v.max_uses then reason := 'Usos agotados';
  elsif v.type = 'recurring' and v.weekdays is not null and not (dow = any(v.weekdays)) then reason := 'Día no permitido';
  elsif v.type = 'recurring' and v.time_from is not null and v.time_to is not null
        and not (now_local::time between v.time_from and v.time_to) then reason := 'Fuera de horario';
  elsif exists (select 1 from blocklist b where b.country_id = g.country_id
                and ((b.dni is not null and b.dni = vis.dni) or (b.plate is not null and b.plate = vis.plate)))
        then reason := 'En lista de bloqueo';
  end if;

  if reason is null then
    if p_direction = 'in' then update visits set uses = uses + 1 where id = v.id; end if;
    insert into access_logs(country_id, lot_id, visit_id, visitor_id, guard_id, direction, result, plate, dni)
    values (g.country_id, v.lot_id, v.id, v.visitor_id, g.id, p_direction, 'allowed', vis.plate, vis.dni);
  else
    insert into access_logs(country_id, lot_id, visit_id, visitor_id, guard_id, direction, result, reason, plate, dni)
    values (g.country_id, v.lot_id, v.id, v.visitor_id, g.id, p_direction, 'denied', reason, vis.plate, vis.dni);
  end if;

  return jsonb_build_object(
    'allowed', reason is null, 'reason', reason,
    'visitor', vis.full_name, 'dni', vis.dni, 'plate', vis.plate,
    'lot', lot_code, 'type', v.type, 'uses', v.uses, 'max_uses', v.max_uses
  );
end $$;

-- Ingreso/egreso manual (DNI/patente) sin QR
create or replace function log_manual_access(
  p_lot uuid, p_name text, p_dni text, p_plate text,
  p_direction access_direction, p_result access_result, p_reason text default null)
returns uuid
language plpgsql security definer set search_path = public as
$$
declare g profiles%rowtype; new_id uuid;
begin
  select * into g from profiles where id = auth.uid() and active and role in ('guard','admin');
  if not found then raise exception 'No autorizado'; end if;
  insert into access_logs(country_id, lot_id, guard_id, direction, result, reason, plate, dni)
  values (g.country_id, p_lot, g.id, p_direction, p_result, coalesce(p_reason, p_name), p_plate, p_dni)
  returning id into new_id;
  return new_id;
end $$;

-- Chequeo de lista de bloqueo (para ingreso manual)
create or replace function is_blocked(p_dni text, p_plate text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from blocklist b
   where b.country_id = current_country()
     and ((p_dni is not null and b.dni = p_dni) or (p_plate is not null and b.plate = p_plate))) $$;

-- Expirar visitas vencidas (programar con pg_cron)
create or replace function expire_visits() returns void
language sql security definer set search_path = public as
$$ update visits set status = 'expired' where status = 'authorized' and valid_to < now() $$;

-- ============ REALTIME ============
alter publication supabase_realtime add table live_requests;
alter publication supabase_realtime add table panic_events;
alter publication supabase_realtime add table access_logs;
