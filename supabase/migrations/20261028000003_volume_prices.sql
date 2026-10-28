-- Volume prices: the price per hour or per track drops the more an artist books in one booking.
--   volume_prices: [{ id, target: 'session' | 'add_on', target_id, min_qty, unit_price }]
--   'session' → hourly rate from min_qty booked hours (hours no time-based price covers);
--   'add_on'  → price per track from min_qty tracks (per_track add-ons) or per hour from min_qty hours
--               (per_hour add-ons). The highest min_qty that's reached applies.
-- Own column, like price_rules, so older apps that save session types and add-ons don't drop it.

alter table public.studios add column if not exists volume_prices jsonb not null default '[]'::jsonb;
do $$ begin
  alter table public.studios add constraint studios_volume_prices_array check (jsonb_typeof(volume_prices) = 'array');
exception when duplicate_object then null; end $$;

create or replace function public.volume_price(p_studio public.studios, p_target text, p_target_id text, p_qty integer, p_default integer)
returns integer
language sql stable set search_path = public
as $$
  select coalesce((
    select (v ->> 'unit_price')::int
    from jsonb_array_elements(coalesce(p_studio.volume_prices, '[]'::jsonb)) as v
    where v ->> 'target' = p_target and v ->> 'target_id' = p_target_id
      and coalesce((v ->> 'unit_price')::int, 0) > 0 and coalesce((v ->> 'min_qty')::int, 0) between 2 and greatest(p_qty, 0)
    order by (v ->> 'min_qty')::int desc
    limit 1), p_default);
$$;

do $$
declare d text;
begin
  select replace(pg_get_functiondef('public.price_booking(public.studios, text, integer, jsonb, text, uuid, timestamptz)'::regprocedure), E'\r', '') into d;
  if position('public.volume_price(' in d) > 0 then return; end if;
  if position('v_rate := (v_type ->> ''hourly_rate'')::int;' in d) = 0
     or position('when ''per_hour'' then (v_addon ->> ''price'')::int * p_hours' in d) = 0 then
    raise exception 'price_booking has changed';
  end if;
  d := replace(d, 'v_rate := (v_type ->> ''hourly_rate'')::int;',
    'v_rate := public.volume_price(p_studio, ''session'', p_session_type_id, p_hours, (v_type ->> ''hourly_rate'')::int);
  v_type := jsonb_set(v_type, ''{hourly_rate}'', to_jsonb(v_rate));');
  d := replace(d, 'when ''per_hour'' then (v_addon ->> ''price'')::int * p_hours',
    'when ''per_hour'' then public.volume_price(p_studio, ''add_on'', v_addon ->> ''id'', p_hours, (v_addon ->> ''price'')::int) * p_hours');
  d := replace(d, 'else (v_addon ->> ''price'')::int * v_qty',
    'else public.volume_price(p_studio, ''add_on'', v_addon ->> ''id'', v_qty, (v_addon ->> ''price'')::int) * v_qty');
  execute d;
end $$;
