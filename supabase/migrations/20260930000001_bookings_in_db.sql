-- EasySesh: booking actions that don't move card money run in the database, so booking works
-- before any edge function is deployed or Stripe is configured. Card flows (charging, capturing,
-- refunding) still use the edge functions; these RPCs raise 'needs_payment_service' for them.
-- Mirrors supabase/functions/_shared/pricing.ts and availability.ts.

-- Integer percentage with half-up rounding (same as pricing.ts `percent`).
create or replace function public.pct(p_amount integer, p_percent integer)
returns integer language sql immutable as $$
  select floor((p_amount::numeric * p_percent + 50) / 100)::int;
$$;

-- Whether [start, start + hours) fits the studio's opening hours (same day or an overnight window).
create or replace function public.fits_opening_hours(p_studio public.studios, p_start timestamptz, p_hours integer)
returns boolean
language plpgsql stable set search_path = public
as $$
declare
  v_local timestamp := p_start at time zone coalesce(nullif(p_studio.timezone, ''), 'UTC');
  v_weekday integer := extract(dow from v_local)::int + 1;  -- 1 = Sunday
  v_minute integer := extract(hour from v_local)::int * 60 + extract(minute from v_local)::int;
  v_duration integer := p_hours * 60;
  v_day integer;
  v_offset integer;
  v_hours jsonb;
  v_opens integer;
  v_closes integer;
begin
  for i in 0..1 loop
    v_day := case when i = 0 then v_weekday when v_weekday = 1 then 7 else v_weekday - 1 end;
    v_offset := i * 24 * 60;
    v_hours := (select h from jsonb_array_elements(p_studio.opening_hours) as h where (h ->> 'weekday')::int = v_day limit 1);
    continue when v_hours is null or coalesce((v_hours ->> 'is_closed')::boolean, false);
    v_opens := (v_hours ->> 'opens_at')::int;
    v_closes := (v_hours ->> 'closes_at')::int;
    if v_closes <= v_opens then v_closes := v_closes + 24 * 60; end if;
    if v_minute + v_offset >= v_opens and v_minute + v_offset + v_duration <= v_closes then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

-- Timing rules: notice, how far ahead, opening hours and conflicts (with buffer).
create or replace function public.check_booking_slot(p_studio public.studios, p_start timestamptz, p_hours integer, p_ignore_booking uuid default null)
returns void
language plpgsql stable security definer set search_path = public
as $$
declare
  v_policy jsonb := coalesce(p_studio.booking_policy, '{}'::jsonb);
  v_notice integer := coalesce((v_policy ->> 'minimum_notice_hours')::int, 0);
  v_ahead integer := coalesce((v_policy ->> 'max_advance_days')::int, 90);
  v_buffer interval := make_interval(mins => coalesce((v_policy ->> 'buffer_minutes')::int, 0));
  v_end timestamptz := p_start + make_interval(hours => p_hours);
begin
  if p_start < now() + make_interval(hours => v_notice) then
    raise exception 'This studio needs at least % hours'' notice.', v_notice;
  end if;
  if p_start > now() + make_interval(days => v_ahead + 1) then
    raise exception 'You can book at most % days ahead.', v_ahead;
  end if;
  if not public.fits_opening_hours(p_studio, p_start, p_hours) then
    raise exception 'slot_unavailable';
  end if;
  if exists (
    select 1 from public.bookings b
    where b.studio_id = p_studio.id and b.id is distinct from p_ignore_booking
      and b.status in ('awaiting_payment', 'pending_approval', 'confirmed')
      and b.starts_at < v_end + v_buffer and b.ends_at > p_start - v_buffer
  ) or exists (
    select 1 from public.blocked_slots s
    where s.studio_id = p_studio.id and s.starts_at < v_end + v_buffer and s.ends_at > p_start - v_buffer
  ) then
    raise exception 'slot_unavailable';
  end if;
end;
$$;

-- Artist creates a booking (held for 30 minutes in awaiting_payment). Price is computed here.
create or replace function public.create_booking(
  p_studio_id uuid,
  p_session_type_id text,
  p_starts_at timestamptz,
  p_hours integer,
  p_add_ons jsonb default '[]'::jsonb,
  p_notes text default ''
) returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_studio public.studios;
  v_type jsonb;
  v_rate integer;
  v_min integer;
  v_session integer;
  v_addons_amount integer := 0;
  v_booked jsonb := '[]'::jsonb;
  v_addon jsonb;
  v_qty integer;
  v_amount integer;
  v_subtotal integer;
  v_fee integer;
  v_total integer;
  v_deposit_pct integer;
  v_deposit integer;
  v_due_now integer;
  v_commission integer;
  v_id uuid := gen_random_uuid();
  v_reference text;
  v_artist_name text;
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'artist' and p.status = 'active') then
    raise exception 'Only artist accounts can book sessions.';
  end if;
  v_studio := (select s from public.studios s where s.id = p_studio_id);
  if v_studio.id is null or v_studio.status <> 'approved' or not v_studio.is_active then
    raise exception 'not_found';
  end if;

  v_type := (select t from jsonb_array_elements(v_studio.session_types) as t where t ->> 'id' = p_session_type_id limit 1);
  if v_type is null then raise exception 'Unknown session type.'; end if;
  v_rate := (v_type ->> 'hourly_rate')::int;
  v_min := coalesce((v_type ->> 'minimum_hours')::int, 1);
  if p_hours is null or p_hours < v_min then
    raise exception 'Minimum % hours for %.', v_min, v_type ->> 'name';
  end if;
  if p_hours > 12 then raise exception 'Sessions can be at most 12 hours.'; end if;

  perform public.check_booking_slot(v_studio, p_starts_at, p_hours);

  -- Add-ons: [{ "id": "...", "quantity": n }]
  for v_addon in select a from jsonb_array_elements(coalesce(v_studio.add_ons, '[]'::jsonb)) as a loop
    v_qty := least(greatest(coalesce((
      select floor((x ->> 'quantity')::numeric)::int from jsonb_array_elements(coalesce(p_add_ons, '[]'::jsonb)) as x
      where x ->> 'id' = v_addon ->> 'id' limit 1), 0), 0), 50);
    continue when v_qty = 0;
    v_amount := case v_addon ->> 'unit'
      when 'per_hour' then (v_addon ->> 'price')::int * p_hours
      when 'per_session' then (v_addon ->> 'price')::int
      else (v_addon ->> 'price')::int * v_qty
    end;
    v_addons_amount := v_addons_amount + v_amount;
    v_booked := v_booked || jsonb_build_object('id', v_addon ->> 'id', 'name', v_addon ->> 'name', 'quantity', v_qty, 'amount', v_amount);
  end loop;

  v_session := v_rate * p_hours;
  v_subtotal := v_session + v_addons_amount;
  v_fee := 0;  -- artists pay the studio's price; EasySesh takes 10% from the studio
  v_total := v_subtotal + v_fee;
  v_deposit_pct := least(greatest(coalesce((v_studio.booking_policy ->> 'deposit_percent')::int, 0), 0), 100);
  v_deposit := case when v_deposit_pct > 0 and v_deposit_pct < 100 then public.pct(v_subtotal, v_deposit_pct) else 0 end;
  v_due_now := case when v_deposit > 0 then v_deposit + v_fee else v_total end;
  v_commission := public.pct(v_subtotal, coalesce(v_studio.platform_fee_percent, 10));

  v_reference := 'ES-' || upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
  v_artist_name := coalesce(nullif((select a.artist_name from public.artist_profiles a where a.id = auth.uid()), ''),
                            (select p.email from public.profiles p where p.id = auth.uid()));

  begin
    insert into public.bookings (id, reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name,
      starts_at, ends_at, hours, add_ons, price, notes, changed_by)
    values (v_id, v_reference, auth.uid(), v_studio.id, v_artist_name, v_studio.name, p_session_type_id, v_type ->> 'name',
      p_starts_at, p_starts_at + make_interval(hours => p_hours), p_hours, v_booked,
      jsonb_build_object(
        'currency', v_studio.currency, 'hourly_rate', v_rate, 'hours', p_hours,
        'session_amount', v_session, 'add_ons_amount', v_addons_amount, 'subtotal', v_subtotal,
        'service_fee', v_fee, 'total', v_total, 'deposit_amount', v_deposit,
        'due_now', v_due_now, 'due_later', v_total - v_due_now,
        'studio_commission', v_commission, 'studio_payout', v_subtotal - v_commission),
      left(coalesce(p_notes, ''), 1000), auth.uid());
  exception when exclusion_violation then
    raise exception 'slot_unavailable' using errcode = '23P01';
  end;
  return (select b from public.bookings b where b.id = v_id);
end;
$$;

-- Artist chooses to pay cash at the studio.
create or replace function public.confirm_cash_booking(p_booking_id uuid)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
  v_studio public.studios;
  v_policy jsonb;
begin
  if v_booking.id is null or v_booking.artist_id <> auth.uid() then raise exception 'not_found'; end if;
  if v_booking.status <> 'awaiting_payment' then raise exception 'This booking is no longer awaiting payment.'; end if;
  v_studio := (select s from public.studios s where s.id = v_booking.studio_id);
  v_policy := coalesce(v_studio.booking_policy, '{}'::jsonb);
  if not coalesce((v_policy ->> 'accepts_cash')::boolean, true) or coalesce((v_policy ->> 'deposit_percent')::int, 0) > 0 then
    raise exception 'This studio only accepts payment in the app.';
  end if;
  update public.bookings set
    status = case when coalesce((v_policy ->> 'instant_book')::boolean, true) then 'confirmed'::public.booking_status else 'pending_approval'::public.booking_status end,
    payment_method = 'cash', payment_status = 'pay_at_studio', changed_by = auth.uid()
  where id = p_booking_id;
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;

-- Who is acting on a booking: 'artist' or 'studio_owner' (approved studio only).
create or replace function public.booking_actor(p_booking public.bookings)
returns text
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_booking.artist_id = auth.uid() then return 'artist'; end if;
  if public.owns_approved_studio(p_booking.studio_id) then return 'studio_owner'; end if;
  raise exception 'forbidden' using errcode = '42501';
end;
$$;

-- Card money involved → the payment service (edge function) has to handle refunds/captures.
create or replace function public.booking_has_card_money(p_booking public.bookings)
returns boolean language sql immutable as $$
  select coalesce(p_booking.payment_method::text, '') <> 'cash'
     and p_booking.payment_status not in ('unpaid', 'pay_at_studio', 'failed');
$$;

create or replace function public.cancel_booking(p_booking_id uuid, p_reason text default '')
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
  v_actor text;
  v_reason text := left(btrim(coalesce(p_reason, '')), 500);
begin
  if v_booking.id is null then raise exception 'not_found'; end if;
  v_actor := public.booking_actor(v_booking);
  if v_booking.status not in ('pending_approval', 'confirmed') or v_booking.starts_at <= now() then
    raise exception 'This booking can no longer be cancelled.';
  end if;
  if v_actor = 'studio_owner' and v_reason = '' then
    raise exception 'Please tell the artist why you''re cancelling.';
  end if;
  if public.booking_has_card_money(v_booking) then raise exception 'needs_payment_service'; end if;
  update public.bookings set
    status = 'cancelled', cancelled_by = v_actor::public.user_role, cancellation_reason = nullif(v_reason, ''),
    payment_status = 'unpaid', changed_by = auth.uid()
  where id = p_booking_id;
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;

create or replace function public.respond_booking(p_booking_id uuid, p_accept boolean, p_message text default null)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
begin
  if v_booking.id is null then raise exception 'not_found'; end if;
  if not public.owns_approved_studio(v_booking.studio_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if v_booking.status <> 'pending_approval' then raise exception 'This request has already been handled.'; end if;
  if public.booking_has_card_money(v_booking) then raise exception 'needs_payment_service'; end if;
  if p_accept then
    update public.bookings set status = 'confirmed', changed_by = auth.uid() where id = p_booking_id;
  else
    update public.bookings set status = 'declined', payment_status = 'unpaid',
      cancellation_reason = nullif(left(btrim(coalesce(p_message, '')), 500), ''), changed_by = auth.uid()
    where id = p_booking_id;
  end if;
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;

-- Same duration and price, new start time. No money moves, so this never needs the payment service.
create or replace function public.reschedule_booking(p_booking_id uuid, p_starts_at timestamptz)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
  v_studio public.studios;
begin
  if v_booking.id is null then raise exception 'not_found'; end if;
  perform public.booking_actor(v_booking);
  if v_booking.status <> 'confirmed' or v_booking.starts_at <= now() then
    raise exception 'This booking can''t be changed.';
  end if;
  v_studio := (select s from public.studios s where s.id = v_booking.studio_id);
  perform public.check_booking_slot(v_studio, p_starts_at, v_booking.hours, v_booking.id);
  begin
    update public.bookings set starts_at = p_starts_at, ends_at = p_starts_at + make_interval(hours => v_booking.hours),
      changed_by = auth.uid()
    where id = p_booking_id;
  exception when exclusion_violation then
    raise exception 'slot_unavailable' using errcode = '23P01';
  end;
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;
