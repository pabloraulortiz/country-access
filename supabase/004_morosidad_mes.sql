-- Morosidad por mes, cargada por el administrador desde la app.
-- Un lote es moroso si tiene algún mes impago hasta el mes actual (inclusive).
-- lots.debt_blocked se recalcula solo; validate_qr y lot_debt_status siguen funcionando igual.

create table if not exists lot_debts (
  lot_id uuid not null references lots(id) on delete cascade,
  period date not null check (period = date_trunc('month', period)::date),   -- primer día del mes
  paid boolean not null default false,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now(),
  primary key (lot_id, period)
);
create index if not exists lot_debts_period_idx on lot_debts(period, paid);

alter table lot_debts enable row level security;
-- Solo administración ve y edita montos/estados; la guardia solo recibe el flag vía lots.debt_blocked.
create policy lot_debts_admin on lot_debts for all
  using (current_role_name() = 'admin' and exists (select 1 from lots l where l.id = lot_id and l.country_id = current_country()))
  with check (current_role_name() = 'admin' and exists (select 1 from lots l where l.id = lot_id and l.country_id = current_country()));

create or replace function recompute_lot_debt(p_lot uuid) returns void
language sql security definer set search_path = public as
$$
  update lots set
    debt_blocked = exists (
      select 1 from lot_debts d
      where d.lot_id = p_lot and not d.paid
        and d.period <= date_trunc('month', now() at time zone 'America/Argentina/Cordoba')::date),
    debt_updated_at = now()
  where id = p_lot
$$;

create or replace function trg_lot_debts_recompute() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  perform recompute_lot_debt(coalesce(new.lot_id, old.lot_id));
  return null;
end $$;

drop trigger if exists lot_debts_recompute on lot_debts;
create trigger lot_debts_recompute after insert or update or delete on lot_debts
  for each row execute function trg_lot_debts_recompute();

-- Recalcular todos (programar el día 1 de cada mes con pg_cron, o llamar a mano)
create or replace function recompute_all_debts() returns void
language sql security definer set search_path = public as
$$ select recompute_lot_debt(id) from lots $$;

-- Marcar en lote: p_codes = códigos de lote (lots.code o lots.external_ref). Devuelve cuántos marcó y cuáles no encontró.
create or replace function mark_debts_bulk(p_period date, p_codes text[])
returns jsonb
language plpgsql security definer set search_path = public as
$$
declare
  per date := date_trunc('month', p_period)::date;
  found_ids uuid[];
  missing text[];
begin
  if current_role_name() <> 'admin' then raise exception 'No autorizado'; end if;

  select array_agg(l.id) into found_ids from lots l
  where l.country_id = current_country()
    and (lower(l.code) = any (select lower(trim(c)) from unnest(p_codes) c)
      or lower(l.external_ref) = any (select lower(trim(c)) from unnest(p_codes) c));

  select array_agg(trim(c)) into missing from unnest(p_codes) c
  where trim(c) <> '' and not exists (
    select 1 from lots l where l.country_id = current_country()
      and (lower(l.code) = lower(trim(c)) or lower(l.external_ref) = lower(trim(c))));

  insert into lot_debts(lot_id, period, paid, updated_by)
  select unnest(found_ids), per, false, auth.uid()
  on conflict (lot_id, period) do update set paid = false, updated_by = auth.uid(), updated_at = now();

  return jsonb_build_object('marked', coalesce(array_length(found_ids, 1), 0), 'missing', coalesce(missing, '{}'));
end $$;
