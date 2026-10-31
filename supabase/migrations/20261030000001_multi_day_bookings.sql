-- Multi-day bookings: a session type can be priced per day ("Day rental", 10 hours a day). The artist
-- picks a number of days (1–30) at the same start time; the price per day can drop with more days
-- (volume_prices with target 'day'); add-ons can be charged per day (e.g. accommodation with meals).
-- A multi-day booking is one booking from the first day's start to the last day's end, so the studio
-- is reserved for the whole stay; every day must still fit the opening hours.
-- New settings live in their own columns so older apps that save a studio's session types and add-ons
-- (and don't know these settings) don't drop them.
--   day_rates:       [{ session_type_id, hours_per_day, day_price }]
--   per_day_add_ons: [add-on id, …]  (per_session add-ons charged once per day)

alter table public.studios add column if not exists day_rates jsonb not null default '[]'::jsonb;
alter table public.studios add column if not exists per_day_add_ons jsonb not null default '[]'::jsonb;
do $$ begin
  alter table public.studios add constraint studios_day_rates_array check (jsonb_typeof(day_rates) = 'array' and jsonb_typeof(per_day_add_ons) = 'array');
exception when duplicate_object then null; end $$;

alter table public.bookings add column if not exists days integer not null default 1;
do $$ begin
  alter table public.bookings add constraint bookings_days_check check (days between 1 and 30);
exception when duplicate_object then null; end $$;

-- price_booking with a number of days (the 7-argument version becomes 1 day).
do $$
declare d text;
begin
  if exists (select 1 from pg_proc where proname = 'price_booking' and pronargs = 8) then return; end if;
  select replace(pg_get_functiondef('public.price_booking(public.studios, text, integer, jsonb, text, uuid, timestamptz)'::regprocedure), E'\r', '') into d;
  if position('v_session := (v_timed ->> ''amount'')::int;' in d) = 0
     or position('when ''per_session'' then (v_addon ->> ''price'')::int' in d) = 0
     or position('p_hours, (v_addon ->> ''price'')::int) * p_hours' in d) = 0
     or position('''hours'', p_hours, ''rate_lines''' in d) = 0 then
    raise exception 'price_booking has changed';
  end if;
  d := replace(d, 'p_starts_at timestamp with time zone)', 'p_starts_at timestamp with time zone, p_days integer)');
  d := replace(d, '  v_timed jsonb;', '  v_timed jsonb;
  v_day jsonb;');
  d := replace(d, 'v_session := (v_timed ->> ''amount'')::int;', 'v_session := (v_timed ->> ''amount'')::int;
  v_day := (select r from jsonb_array_elements(coalesce(p_studio.day_rates, ''[]''::jsonb)) as r
            where r ->> ''session_type_id'' = p_session_type_id and coalesce((r ->> ''day_price'')::int, 0) > 0 limit 1);
  if p_days is null or p_days < 1 or p_days > 30 then raise exception ''Book between 1 and 30 days.''; end if;
  if v_day is not null then
    v_rate := public.volume_price(p_studio, ''day'', p_session_type_id, p_days, (v_day ->> ''day_price'')::int);
    v_session := v_rate * p_days;
    v_timed := jsonb_build_object(''amount'', v_session, ''lines'', ''[]''::jsonb);
  elsif p_days > 1 then
    raise exception ''This session type is booked by the hour.'';
  end if;');
  d := replace(d, 'when ''per_session'' then (v_addon ->> ''price'')::int',
    'when ''per_session'' then (v_addon ->> ''price'')::int * case when coalesce(p_studio.per_day_add_ons, ''[]''::jsonb) ? (v_addon ->> ''id'') then p_days else 1 end');
  d := replace(d, 'p_hours, (v_addon ->> ''price'')::int) * p_hours', 'p_hours, (v_addon ->> ''price'')::int) * p_hours * p_days');
  d := replace(d, '''hours'', p_hours, ''rate_lines''',
    '''hours'', p_hours, ''days'', p_days, ''day_rate'', case when v_day is null then null else v_rate end, ''rate_lines''');
  execute d;
end $$;
revoke execute on function public.price_booking(public.studios, text, integer, jsonb, text, uuid, timestamptz, integer) from public, anon, authenticated;

create or replace function public.price_booking(p_studio public.studios, p_session_type_id text, p_hours integer, p_add_ons jsonb, p_promo_code text, p_artist uuid, p_starts_at timestamptz)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select public.price_booking(p_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, p_artist, p_starts_at, 1);
$$;
revoke execute on function public.price_booking(public.studios, text, integer, jsonb, text, uuid, timestamptz) from public, anon, authenticated;

-- Quote for a number of days (the website sends it).
create or replace function public.quote_booking(p_studio_id uuid, p_session_type_id text, p_hours integer, p_add_ons jsonb, p_promo_code text, p_starts_at timestamptz, p_days integer)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.id = p_studio_id);
begin
  if v_studio.id is null or v_studio.status <> 'approved' or not v_studio.is_active then raise exception 'not_found'; end if;
  if p_hours is null or p_hours < 1 or p_hours > 12 then raise exception 'Sessions can be at most 12 hours.'; end if;
  if p_promo_code is not null and auth.uid() is null then raise exception 'Please sign in to continue.'; end if;
  return public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid(), p_starts_at, coalesce(p_days, 1)) -> 'price';
end;
$$;
grant execute on function public.quote_booking(uuid, text, integer, jsonb, text, timestamptz, integer) to anon, authenticated;

-- book_session_days: book_session with a number of days. (A book_session overload with an extra
-- defaulted argument would make calls without it ambiguous, so it gets its own name; book_session
-- now books 1 day through it.)
do $$
declare d text;
begin
  if exists (select 1 from pg_proc where proname = 'book_session_days') then return; end if;
  select replace(pg_get_functiondef('public.book_session(uuid, text, timestamptz, integer, jsonb, text, text)'::regprocedure), E'\r', '') into d;
  if position('perform public.check_booking_slot(v_studio, p_starts_at, p_hours);' in d) = 0
     or position('if p_hours is null or p_hours < v_min then' in d) = 0
     or position('auth.uid(), p_starts_at);' in d) = 0
     or position('p_starts_at, p_starts_at + make_interval(hours => p_hours), p_hours,' in d) = 0 then
    raise exception 'book_session has changed';
  end if;
  d := replace(d, 'FUNCTION public.book_session(', 'FUNCTION public.book_session_days(');
  d := replace(d, 'p_promo_code text DEFAULT NULL::text)', 'p_promo_code text DEFAULT NULL::text, p_days integer DEFAULT 1)');
  d := replace(d, '  v_artist_name text;', '  v_artist_name text;
  v_day jsonb;
  i integer;');
  d := replace(d, 'if p_hours is null or p_hours < v_min then', 'if p_days is null or p_days < 1 or p_days > 30 then raise exception ''Book between 1 and 30 days.''; end if;
  v_day := (select r from jsonb_array_elements(coalesce(v_studio.day_rates, ''[]''::jsonb)) as r
            where r ->> ''session_type_id'' = p_session_type_id and coalesce((r ->> ''day_price'')::int, 0) > 0 limit 1);
  if v_day is not null then
    p_hours := least(greatest(coalesce((v_day ->> ''hours_per_day'')::int, 8), 1), 12);
  elsif p_days > 1 then
    raise exception ''This session type is booked by the hour.'';
  end if;
  if v_day is null and (p_hours is null or p_hours < v_min) then');
  d := replace(d, 'perform public.check_booking_slot(v_studio, p_starts_at, p_hours);',
    'for i in 0 .. p_days - 1 loop
    perform public.check_booking_slot(v_studio, p_starts_at + make_interval(days => i), p_hours);
  end loop;');
  d := replace(d, 'auth.uid(), p_starts_at);', 'auth.uid(), p_starts_at, p_days);');
  d := replace(d, 'starts_at, ends_at, hours, add_ons, price, notes, changed_by, promo_code_id)',
                  'starts_at, ends_at, hours, days, add_ons, price, notes, changed_by, promo_code_id)');
  d := replace(d, 'p_starts_at, p_starts_at + make_interval(hours => p_hours), p_hours,',
                  'p_starts_at, p_starts_at + make_interval(days => p_days - 1, hours => p_hours), p_hours, p_days,');
  execute d;
end $$;
revoke execute on function public.book_session_days(uuid, text, timestamptz, integer, jsonb, text, text, integer) from public, anon;
grant execute on function public.book_session_days(uuid, text, timestamptz, integer, jsonb, text, text, integer) to authenticated;

-- The apps' book_session books 1 day (for a day-priced session type: one day at its hours).
create or replace function public.book_session(p_studio_id uuid, p_session_type_id text, p_starts_at timestamptz, p_hours integer,
  p_add_ons jsonb default '[]'::jsonb, p_notes text default ''::text, p_promo_code text default null::text)
returns public.bookings
language sql security definer set search_path = public
as $$
  select * from public.book_session_days(p_studio_id, p_session_type_id, p_starts_at, p_hours, p_add_ons, p_notes, p_promo_code, 1);
$$;

-- Moving a multi-day booking keeps all its days (each day must fit again).
do $$
declare d text;
begin
  select replace(pg_get_functiondef('public.reschedule_booking'::regproc), E'\r', '') into d;
  if position('greatest(v_booking.days, 1)' in d) > 0 then return; end if;
  d := replace(d, '  v_studio public.studios;', '  v_studio public.studios;
  i integer;');
  d := replace(d, 'perform public.check_booking_slot(v_studio, p_starts_at, v_booking.hours, v_booking.id);',
    'for i in 0 .. greatest(v_booking.days, 1) - 1 loop
    perform public.check_booking_slot(v_studio, p_starts_at + make_interval(days => i), v_booking.hours, v_booking.id);
  end loop;');
  d := replace(d, 'ends_at = p_starts_at + make_interval(hours => v_booking.hours)',
    'ends_at = p_starts_at + make_interval(days => greatest(v_booking.days, 1) - 1, hours => v_booking.hours)');
  execute d;
end $$;
