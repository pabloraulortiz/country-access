-- 007: turno obligatorio para la guardia, ingreso por DNI/patente y novedades de ronda.
-- Ejecutar después de 006.

-- ---------- Turno obligatorio ----------
alter table countries add column if not exists enforce_shift boolean not null default true;

-- true si el guardia tiene un turno asignado ahora (15 min antes del inicio hasta 30 min después del fin).
-- Si el country desactivó la exigencia, siempre devuelve true.
create or replace function guard_on_shift(p_uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as
$$
  select coalesce((select not c.enforce_shift
                   from profiles p join countries c on c.id = p.country_id
                   where p.id = p_uid), false)
      or exists (
        select 1
        from shift_assignments a
        join shifts s on s.id = a.shift_id
        cross join lateral (select (a.shift_date + s.start_time) as st) x
        cross join lateral (select x.st + case when s.end_time > s.start_time
                                               then s.end_time - s.start_time
                                               else s.end_time - s.start_time + interval '24 hours' end as en) y
        where a.guard_id = p_uid
          and (now() at time zone 'America/Argentina/Cordoba')
              between x.st - interval '15 minutes' and y.en + interval '30 minutes')
$$;

-- validate_qr: exige turno a los guardias; la SALIDA nunca se bloquea (solo se registra).
create or replace function validate_qr(p_token text, p_direction access_direction default 'in')
returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  v visits%rowtype;
  vis visitors%rowtype;
  lot_code text;
  lot_debt boolean;
  blk boolean;
  g profiles%rowtype;
  reason text := null;
  warning text := null;
  now_local timestamp := (now() at time zone 'America/Argentina/Cordoba');
  dow int := extract(isodow from now_local)::int;
begin
  select * into g from profiles where id = auth.uid() and active and role in ('guard','admin');
  if not found then raise exception 'No autorizado'; end if;
  if g.role = 'guard' and not guard_on_shift(g.id) then raise exception 'Fuera de turno'; end if;

  select * into v from visits where qr_token = p_token and country_id = g.country_id;
  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'QR inválido');
  end if;

  select * into vis from visitors where id = v.visitor_id;
  select code, debt_blocked into lot_code, lot_debt from lots where id = v.lot_id;
  select block_on_debt into blk from countries where id = g.country_id;

  if p_direction = 'in' then
    if v.status <> 'authorized' then reason := 'Visita ' || v.status;
    elsif now() < v.valid_from then reason := 'Aún no es válida';
    elsif now() > v.valid_to then reason := 'Vencida';
    elsif v.uses >= v.max_uses then reason := 'Usos agotados';
    elsif v.type = 'recurring' and v.weekdays is not null and not (dow = any(v.weekdays)) then reason := 'Día no permitido';
    elsif v.type = 'recurring' and v.time_from is not null and v.time_to is not null
          and not (now_local::time between v.time_from and v.time_to) then reason := 'Fuera de horario';
    elsif exists (select 1 from blocklist b where b.country_id = g.country_id
                  and ((b.dni is not null and b.dni = vis.dni) or (b.plate is not null and b.plate = vis.plate)))
          then reason := 'En lista de bloqueo';
    elsif lot_debt and blk then reason := 'Lote con deuda - consultar administración';
    end if;

    if reason is null and lot_debt then warning := 'Lote con deuda'; end if;
  end if;

  if reason is null then
    if p_direction = 'in' then update visits set uses = uses + 1 where id = v.id; end if;
    insert into access_logs(country_id, lot_id, visit_id, visitor_id, guard_id, direction, result, reason, plate, dni)
    values (g.country_id, v.lot_id, v.id, v.visitor_id, g.id, p_direction, 'allowed', warning, vis.plate, vis.dni);
  else
    insert into access_logs(country_id, lot_id, visit_id, visitor_id, guard_id, direction, result, reason, plate, dni)
    values (g.country_id, v.lot_id, v.id, v.visitor_id, g.id, p_direction, 'denied', reason, vis.plate, vis.dni);
  end if;

  return jsonb_build_object(
    'allowed', reason is null, 'reason', reason, 'warning', warning,
    'visitor', vis.full_name, 'dni', vis.dni, 'plate', vis.plate,
    'lot', lot_code, 'type', v.type,
    'uses', v.uses + case when reason is null and p_direction = 'in' then 1 else 0 end,
    'max_uses', v.max_uses
  );
end $$;

-- Ingreso/egreso manual: exige turno a los guardias
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
  if g.role = 'guard' and not guard_on_shift(g.id) then raise exception 'Fuera de turno'; end if;
  insert into access_logs(country_id, lot_id, guard_id, direction, result, reason, plate, dni)
  values (g.country_id, p_lot, g.id, p_direction, p_result, coalesce(p_reason, p_name), p_plate, p_dni)
  returning id into new_id;
  return new_id;
end $$;

-- Pedido en vivo al propietario: solo guardias con turno
drop policy if exists live_guard_insert on live_requests;
create policy live_guard_insert on live_requests for insert
  with check (country_id = current_country() and guard_id = auth.uid()
              and current_role_name() = 'guard' and guard_on_shift());
-- (El botón de pánico NO exige turno a propósito.)

-- ---------- Ingreso por DNI o patente ----------
-- Busca visitas autorizadas por DNI y/o patente.
--  - una sola coincidencia  -> la valida y registra (igual que escanear el QR)
--  - varias                 -> devuelve las opciones para que la guardia elija
--  - ninguna                -> {found:false}; la guardia consulta al propietario
create or replace function validate_identity(p_dni text, p_plate text, p_direction access_direction default 'in')
returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  g profiles%rowtype;
  d text := nullif(regexp_replace(coalesce(p_dni, ''), '[^0-9]', '', 'g'), '');
  pl text := upper(regexp_replace(coalesce(p_plate, ''), '[^A-Za-z0-9]', '', 'g'));
  cands jsonb;
  n int;
begin
  select * into g from profiles where id = auth.uid() and active and role in ('guard','admin');
  if not found then raise exception 'No autorizado'; end if;
  if g.role = 'guard' and not guard_on_shift(g.id) then raise exception 'Fuera de turno'; end if;

  if d is null and pl = '' then
    return jsonb_build_object('found', false, 'allowed', false, 'reason', 'Ingresá DNI o patente');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'token', v.qr_token, 'visitor', vis.full_name, 'lot', l.code, 'valid_to', v.valid_to)
           order by v.valid_from), '[]'::jsonb)
  into cands
  from visits v
  join visitors vis on vis.id = v.visitor_id
  join lots l on l.id = v.lot_id
  where v.country_id = g.country_id
    and ((d is not null and regexp_replace(coalesce(vis.dni, ''), '[^0-9]', '', 'g') = d)
      or (pl <> '' and upper(regexp_replace(coalesce(vis.plate, ''), '[^A-Za-z0-9]', '', 'g')) = pl))
    and ((p_direction = 'in' and v.status = 'authorized'
          and now() between v.valid_from and v.valid_to and v.uses < v.max_uses)
      or (p_direction = 'out' and v.uses > 0 and v.valid_from <= now()
          and v.valid_to > now() - interval '2 days'));

  n := jsonb_array_length(cands);
  if n = 0 then
    return jsonb_build_object('found', false, 'allowed', false, 'reason', 'Sin autorización vigente');
  elsif n = 1 then
    return validate_qr(cands->0->>'token', p_direction) || jsonb_build_object('found', true);
  else
    return jsonb_build_object('found', true, 'multiple', true, 'options', cands);
  end if;
end $$;

-- ---------- Novedades de ronda ----------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'patrol_kind') then
    create type patrol_kind as enum ('clear', 'incident');
  end if;
end $$;

create table if not exists patrol_reports (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references countries(id),
  guard_id uuid not null references profiles(id),
  kind patrol_kind not null,
  lot_id uuid references lots(id),
  description text,
  created_at timestamptz not null default now(),
  check (kind = 'clear' or length(trim(coalesce(description, ''))) > 0)
);
create index if not exists patrol_reports_idx on patrol_reports(country_id, created_at desc);

alter table patrol_reports enable row level security;

create policy patrol_read on patrol_reports for select
  using (country_id = current_country() and current_role_name() in ('admin', 'guard'));
create policy patrol_insert on patrol_reports for insert
  with check (country_id = current_country() and guard_id = auth.uid()
              and current_role_name() = 'guard' and guard_on_shift());

alter publication supabase_realtime add table patrol_reports;
