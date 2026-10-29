-- Morosidad: el sistema SQL Server empuja el estado por lote a Supabase.
-- Ejecutar después de schema.sql.

alter table lots add column if not exists external_ref text;      -- código del lote en tu sistema administrativo
create unique index if not exists lots_external_ref_uq on lots(country_id, external_ref) where external_ref is not null;

alter table lots add column if not exists debt_blocked boolean not null default false;
alter table lots add column if not exists debt_updated_at timestamptz;

-- true = bloquea el ingreso de visitas del lote morosos; false = solo avisa a la guardia
alter table countries add column if not exists block_on_debt boolean not null default false;

-- Sync desde el sistema administrativo. Solo service_role.
-- p_items: [{"ref":"MZ12-L05","debt":true}, ...]
create or replace function sync_lot_debt(p_country uuid, p_items jsonb)
returns int
language plpgsql security definer set search_path = public as
$$
declare n int;
begin
  if auth.role() <> 'service_role' then raise exception 'No autorizado'; end if;
  with src as (
    select (e->>'ref') as ref, coalesce((e->>'debt')::boolean, false) as debt
    from jsonb_array_elements(p_items) e
  )
  update lots l set debt_blocked = s.debt, debt_updated_at = now()
  from src s
  where l.country_id = p_country and l.external_ref = s.ref;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function sync_lot_debt(uuid, jsonb) from public, anon, authenticated;
grant execute on function sync_lot_debt(uuid, jsonb) to service_role;

-- validate_qr con control de morosidad
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

  select * into v from visits where qr_token = p_token and country_id = g.country_id;
  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'QR inválido');
  end if;

  select * into vis from visitors where id = v.visitor_id;
  select code, debt_blocked into lot_code, lot_debt from lots where id = v.lot_id;
  select block_on_debt into blk from countries where id = g.country_id;

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
  elsif p_direction = 'in' and lot_debt and blk then reason := 'Lote con deuda - consultar administración';
  end if;

  if reason is null and p_direction = 'in' and lot_debt then
    warning := 'Lote con deuda';
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
    'lot', lot_code, 'type', v.type, 'uses', v.uses, 'max_uses', v.max_uses
  );
end $$;

-- Estado de deuda de un lote para el ingreso manual (la guardia solo ve el flag, nunca montos)
create or replace function lot_debt_status(p_lot uuid)
returns jsonb
language sql stable security definer set search_path = public as
$$
  select jsonb_build_object('debt', l.debt_blocked, 'block', c.block_on_debt)
  from lots l join countries c on c.id = l.country_id
  where l.id = p_lot and l.country_id = current_country()
$$;
