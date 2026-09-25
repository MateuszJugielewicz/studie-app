-- EasySesh: optional check-in when the artist arrives, and the studio confirming the arrival.
-- Records time and (for the artist) how far the phone was from the studio, as evidence in
-- no-show or payment disputes. EasySesh recommends it; a studio can switch it off, in which case
-- EasySesh can't promise a refund if something goes wrong.

alter table public.bookings
  add column if not exists artist_checked_in_at timestamptz,
  add column if not exists artist_check_in_distance_m integer,
  add column if not exists studio_confirmed_arrival_at timestamptz;

-- Great-circle distance in metres.
create or replace function public.distance_m(p_lat1 double precision, p_lng1 double precision, p_lat2 double precision, p_lng2 double precision)
returns integer language sql immutable as $$
  select round(6371000 * 2 * asin(sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
    cos(radians(p_lat1)) * cos(radians(p_lat2)) * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
  )))::int;
$$;

-- Artist checks in (from 60 minutes before the session until it ends). Location is optional.
create or replace function public.check_in_booking(p_booking_id uuid, p_lat double precision default null, p_lng double precision default null)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
  v_studio public.studios;
  v_distance integer;
begin
  if v_booking.id is null or v_booking.artist_id <> auth.uid() then raise exception 'not_found'; end if;
  if v_booking.status <> 'confirmed' then raise exception 'Only confirmed bookings can be checked in.'; end if;
  if now() < v_booking.starts_at - interval '60 minutes' or now() > v_booking.ends_at then
    raise exception 'You can check in from 1 hour before your session until it ends.';
  end if;
  if v_booking.artist_checked_in_at is not null then return v_booking; end if;
  v_studio := (select s from public.studios s where s.id = v_booking.studio_id);
  -- Studios can switch check-in off (booking_policy.check_in_enabled); EasySesh recommends keeping it on.
  if not coalesce((v_studio.booking_policy ->> 'check_in_enabled')::boolean, true) then
    raise exception 'This studio has turned off check-in.';
  end if;
  if p_lat is not null and p_lng is not null then
    v_distance := public.distance_m(p_lat, p_lng, v_studio.latitude, v_studio.longitude);
  end if;
  update public.bookings set artist_checked_in_at = now(), artist_check_in_distance_m = v_distance
  where id = p_booking_id;
  perform public.notify(v_studio.owner_id, 'booking_changed', v_booking.artist_name || ' has arrived',
    'Checked in for ' || v_booking.session_type_name ||
      case when v_distance is null then '.' when v_distance <= 300 then ' at the studio.' else ' (' || v_distance || ' m from the studio).' end,
    v_booking.id, null, v_booking.studio_id);
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;

-- Studio confirms the artist showed up.
create or replace function public.confirm_artist_arrival(p_booking_id uuid)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
begin
  if v_booking.id is null or not public.owns_approved_studio(v_booking.studio_id) then raise exception 'not_found'; end if;
  if v_booking.status not in ('confirmed', 'completed') then raise exception 'Only confirmed bookings can be marked as arrived.'; end if;
  if now() < v_booking.starts_at - interval '60 minutes' then raise exception 'The session hasn''t started yet.'; end if;
  update public.bookings set studio_confirmed_arrival_at = coalesce(studio_confirmed_arrival_at, now()) where id = p_booking_id;
  return (select b from public.bookings b where b.id = p_booking_id);
end;
$$;
