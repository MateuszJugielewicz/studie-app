-- Time-based prices: a studio can charge a different hourly rate at certain times, per session type
-- (e.g. "Evening" Mon–Fri 18–24, "Weekend" Sat–Sun all day). Each booked hour is priced at the first
-- rule that matches when that hour starts (in the studio's time zone); hours no rule matches use the
-- session type's normal rate. The rules live in their own column so older apps that save a studio's
-- session types don't drop them.
--   price_rules: [{ id, session_type_id, label, weekdays: [1..7] (1 = Sunday), from: minutes, to: minutes
--                   (to may be 1440; from > to wraps past midnight), hourly_rate }]

alter table public.studios add column if not exists price_rules jsonb not null default '[]'::jsonb;
do $$ begin
  alter table public.studios add constraint studios_price_rules_array check (jsonb_typeof(price_rules) = 'array');
exception when duplicate_object then null; end $$;

-- The session's price at a given start time: { amount, lines: [{ label, hourly_rate, hours, amount }] }.
create or replace function public.session_price(p_studio public.studios, p_type jsonb, p_starts_at timestamptz, p_hours integer)
returns jsonb
language plpgsql stable set search_path = public
as $$
declare
  v_base integer := (p_type ->> 'hourly_rate')::int;
  v_local timestamp;
  v_dow integer;
  v_min integer;
  v_rule jsonb;
  v_rate integer;
  v_label text;
  v_amount integer := 0;
  v_lines jsonb := '[]'::jsonb;
  v_key text;
  v_index integer;
  i integer;
begin
  for i in 0 .. greatest(p_hours, 0) - 1 loop
    v_rule := null;
    if p_starts_at is not null then
      v_local := (p_starts_at + make_interval(hours => i)) at time zone coalesce(nullif(p_studio.timezone, ''), 'Europe/Copenhagen');
      v_dow := extract(dow from v_local)::int + 1;
      v_min := extract(hour from v_local)::int * 60 + extract(minute from v_local)::int;
      select r into v_rule
      from jsonb_array_elements(coalesce(p_studio.price_rules, '[]'::jsonb)) with ordinality as x (r, n)
      where r ->> 'session_type_id' = p_type ->> 'id'
        and coalesce((r ->> 'hourly_rate')::int, 0) > 0
        and r -> 'weekdays' @> to_jsonb(v_dow)
        and case
              when (r ->> 'from')::int <= (r ->> 'to')::int then v_min >= (r ->> 'from')::int and v_min < (r ->> 'to')::int
              else v_min >= (r ->> 'from')::int or v_min < (r ->> 'to')::int
            end
      order by n
      limit 1;
    end if;
    v_rate := coalesce((v_rule ->> 'hourly_rate')::int, v_base);
    v_label := case when v_rule is null then null else nullif(btrim(v_rule ->> 'label'), '') end;
    v_amount := v_amount + v_rate;

    -- Group the hours into lines by label and rate.
    v_key := coalesce(v_label, '') || '|' || v_rate;
    v_index := (select (n - 1)::int from jsonb_array_elements(v_lines) with ordinality as l (line, n)
                where coalesce(line ->> 'label', '') || '|' || (line ->> 'hourly_rate') = v_key limit 1);
    if v_index is null then
      v_lines := v_lines || jsonb_build_object('label', v_label, 'hourly_rate', v_rate, 'hours', 1, 'amount', v_rate);
    else
      v_lines := jsonb_set(v_lines, array[v_index::text], jsonb_build_object('label', v_label, 'hourly_rate', v_rate,
        'hours', (v_lines -> v_index ->> 'hours')::int + 1, 'amount', (v_lines -> v_index ->> 'amount')::int + v_rate));
    end if;
  end loop;
  return jsonb_build_object('amount', v_amount, 'lines', v_lines);
end;
$$;

-- price_booking with the session's start time (the old signature passes no time and so uses normal rates).
do $$
declare d text;
begin
  select replace(pg_get_functiondef('public.price_booking(public.studios, text, integer, jsonb, text, uuid)'::regprocedure), E'\r', '') into d;
  if position('v_session := v_rate * p_hours;' in d) = 0 then raise exception 'price_booking has changed'; end if;
  d := replace(d, 'p_promo_code text, p_artist uuid)', 'p_promo_code text, p_artist uuid, p_starts_at timestamp with time zone)');
  d := replace(d, '  v_due_now integer;', '  v_due_now integer;
  v_timed jsonb;');
  d := replace(d, 'v_session := v_rate * p_hours;', 'v_timed := public.session_price(p_studio, v_type, p_starts_at, p_hours);
  v_session := (v_timed ->> ''amount'')::int;');
  d := replace(d, '''currency'', p_studio.currency, ''hourly_rate'', v_rate, ''hours'', p_hours,',
                  '''currency'', p_studio.currency, ''hourly_rate'', v_rate, ''hours'', p_hours, ''rate_lines'', v_timed -> ''lines'',');
  execute d;
end $$;
revoke execute on function public.price_booking(public.studios, text, integer, jsonb, text, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.price_booking(p_studio public.studios, p_session_type_id text, p_hours integer, p_add_ons jsonb, p_promo_code text, p_artist uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select public.price_booking(p_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, p_artist, null::timestamptz);
$$;

-- A quote for a specific start time (the website sends it; older apps use the version without a time).
create or replace function public.quote_booking(p_studio_id uuid, p_session_type_id text, p_hours integer, p_add_ons jsonb, p_promo_code text, p_starts_at timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.id = p_studio_id);
begin
  if v_studio.id is null or v_studio.status <> 'approved' or not v_studio.is_active then raise exception 'not_found'; end if;
  if p_hours is null or p_hours < 1 or p_hours > 12 then raise exception 'Sessions can be at most 12 hours.'; end if;
  if p_promo_code is not null and auth.uid() is null then raise exception 'Please sign in to continue.'; end if;
  return public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid(), p_starts_at) -> 'price';
end;
$$;
grant execute on function public.quote_booking(uuid, text, integer, jsonb, text, timestamptz) to anon, authenticated;

-- Bookings are priced at their start time.
do $$
declare d text;
begin
  select replace(pg_get_functiondef('public.book_session'::regproc), E'\r', '') into d;
  if position('p_promo_code, auth.uid(), p_starts_at)' in d) > 0 then return; end if;
  if position('public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid())' in d) = 0 then
    raise exception 'book_session has changed';
  end if;
  execute replace(d, 'public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid())',
                     'public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid(), p_starts_at)');
end $$;
