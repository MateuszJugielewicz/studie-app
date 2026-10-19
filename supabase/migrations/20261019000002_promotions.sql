-- Promotions: studio offers (automatic, e.g. "Mixing 50% off") and promo codes (typed in when booking).
--
-- Who pays:
--   * Studio offers and studio promo codes come off the studio's price: the studio's earnings and
--     EasySesh's 10% are both calculated on the discounted price.
--   * EasySesh promo codes (made by an admin) are paid by EasySesh: the studio is paid as if there
--     were no code. The discount is stored as a negative `service_fee`, so total = subtotal +
--     service_fee and EasySesh's take (studio_commission + service_fee) stay correct everywhere
--     (payment records, admin revenue, cash fee balance).
-- Price breakdown fields added: original_subtotal, offer_discount, promo_discount, promo_code, discounts[].

-- ---------------------------------------------------------------------------
-- Studio offers
-- ---------------------------------------------------------------------------
create table if not exists public.studio_offers (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  title text not null,
  percent_off integer not null check (percent_off between 5 and 90),
  -- everything | sessions (all session types) | add_ons (all extras) | session_type | add_on (target_id)
  applies_to text not null default 'everything' check (applies_to in ('everything', 'sessions', 'add_ons', 'session_type', 'add_on')),
  target_id text,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint studio_offers_target check ((applies_to in ('session_type', 'add_on')) = (target_id is not null)),
  constraint studio_offers_title check (char_length(btrim(title)) between 2 and 60)
);
create index if not exists studio_offers_studio on public.studio_offers (studio_id);
alter table public.studio_offers enable row level security;

create policy "studio_offers: read live" on public.studio_offers for select using (
  (is_active and (ends_at is null or ends_at > now())
   and exists (select 1 from public.studios s where s.id = studio_id and s.status = 'approved' and s.is_active))
  or public.owns_studio(studio_id) or public.is_admin()
);
create policy "studio_offers: owner insert" on public.studio_offers for insert with check (public.owns_studio(studio_id) or public.is_admin());
create policy "studio_offers: owner update" on public.studio_offers for update using (public.owns_studio(studio_id) or public.is_admin())
  with check (public.owns_studio(studio_id) or public.is_admin());
create policy "studio_offers: owner remove" on public.studio_offers for delete using (public.owns_studio(studio_id) or public.is_admin());

-- At most 10 offers per studio; the target must exist in the listing.
create or replace function public.validate_studio_offer()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios := (select x from public.studios x where x.id = new.studio_id);
begin
  if tg_op = 'UPDATE' then new.studio_id := old.studio_id; new.created_at := old.created_at; end if;
  new.title := btrim(new.title);
  if tg_op = 'INSERT' and (select count(*) from public.studio_offers o where o.studio_id = new.studio_id) >= 10 then
    raise exception 'A studio can have at most 10 offers.';
  end if;
  if new.applies_to = 'session_type'
     and not exists (select 1 from jsonb_array_elements(s.session_types) t where t ->> 'id' = new.target_id) then
    raise exception 'Choose one of your session types.';
  end if;
  if new.applies_to = 'add_on'
     and not exists (select 1 from jsonb_array_elements(s.add_ons) a where a ->> 'id' = new.target_id) then
    raise exception 'Choose one of your extras.';
  end if;
  return new;
end;
$$;
create trigger validate_studio_offer before insert or update on public.studio_offers
  for each row execute function public.validate_studio_offer();

-- ---------------------------------------------------------------------------
-- Promo codes
-- ---------------------------------------------------------------------------
create table if not exists public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  -- null = an EasySesh code (made by an admin), valid at every studio and paid by EasySesh.
  studio_id uuid references public.studios (id) on delete cascade,
  percent_off integer not null check (percent_off between 1 and 90),
  description text not null default '',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  max_uses integer check (max_uses is null or max_uses > 0),
  max_uses_per_user integer not null default 1 check (max_uses_per_user between 1 and 100),
  is_active boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint promo_codes_format check (code ~ '^[A-Z0-9]{3,20}$'),
  constraint promo_codes_platform_max check (studio_id is not null or percent_off <= 50)
);
create unique index if not exists promo_codes_code on public.promo_codes (code);
alter table public.promo_codes enable row level security;

-- Codes aren't listed publicly (they're checked with check_promo_code).
create policy "promo_codes: owner or admin read" on public.promo_codes for select
  using ((studio_id is not null and public.owns_studio(studio_id)) or public.is_admin());
create policy "promo_codes: owner or admin insert" on public.promo_codes for insert
  with check ((studio_id is not null and public.owns_studio(studio_id)) or public.is_admin());
create policy "promo_codes: owner or admin update" on public.promo_codes for update
  using ((studio_id is not null and public.owns_studio(studio_id)) or public.is_admin())
  with check ((studio_id is not null and public.owns_studio(studio_id)) or public.is_admin());
create policy "promo_codes: owner or admin remove" on public.promo_codes for delete
  using ((studio_id is not null and public.owns_studio(studio_id)) or public.is_admin());

create or replace function public.guard_promo_code()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.code := upper(btrim(new.code));
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    if new.studio_id is not null and not public.is_admin()
       and (select count(*) from public.promo_codes p where p.studio_id = new.studio_id) >= 50 then
      raise exception 'A studio can have at most 50 promo codes.';
    end if;
  else
    new.studio_id := old.studio_id;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  if exists (select 1 from public.promo_codes p where p.code = new.code and p.id <> new.id) then
    raise exception 'This code is already taken. Try another one.';
  end if;
  return new;
end;
$$;
create trigger guard_promo_code before insert or update on public.promo_codes
  for each row execute function public.guard_promo_code();

alter table public.bookings add column if not exists promo_code_id uuid references public.promo_codes (id) on delete set null;
create index if not exists bookings_promo_code on public.bookings (promo_code_id) where promo_code_id is not null;

-- How often each code was used (only bookings the viewer can see count: studios see their own).
create or replace view public.promo_code_usage with (security_invoker = true) as
select b.promo_code_id, count(*)::int as uses
from public.bookings b
where b.promo_code_id is not null and b.status not in ('expired', 'declined', 'cancelled')
group by b.promo_code_id;

-- The code if the artist can use it at this studio now; otherwise a friendly error.
create or replace function public.find_promo_code(p_studio_id uuid, p_code text, p_artist uuid)
returns public.promo_codes
language plpgsql stable security definer set search_path = public
as $$
declare
  c public.promo_codes := (select p from public.promo_codes p where p.code = upper(btrim(coalesce(p_code, ''))));
begin
  if c.id is null or not c.is_active or c.starts_at > now() or (c.studio_id is not null and c.studio_id <> p_studio_id) then
    raise exception 'This promo code isn''t valid for this studio.';
  end if;
  if c.ends_at is not null and c.ends_at <= now() then raise exception 'This promo code has expired.'; end if;
  if c.max_uses is not null and (select count(*) from public.bookings b
      where b.promo_code_id = c.id and b.status not in ('expired', 'declined', 'cancelled')) >= c.max_uses then
    raise exception 'This promo code has been used up.';
  end if;
  if (select count(*) from public.bookings b
      where b.promo_code_id = c.id and b.artist_id = p_artist and b.status not in ('expired', 'declined', 'cancelled')) >= c.max_uses_per_user then
    raise exception 'You''ve already used this promo code.';
  end if;
  return c;
end;
$$;
revoke execute on function public.find_promo_code(uuid, text, uuid) from public, anon, authenticated;

-- Booking page: "Apply" button.
create or replace function public.check_promo_code(p_studio_id uuid, p_code text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  c public.promo_codes;
begin
  if auth.uid() is null then raise exception 'Please sign in to continue.'; end if;
  c := public.find_promo_code(p_studio_id, p_code, auth.uid());
  return jsonb_build_object('code', c.code, 'percent_off', c.percent_off, 'description', c.description,
                            'by_easysesh', c.studio_id is null, 'ends_at', c.ends_at);
end;
$$;
revoke execute on function public.check_promo_code(uuid, text) from public, anon;
grant execute on function public.check_promo_code(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Pricing with discounts (used by create_booking and the booking page's price summary)
-- ---------------------------------------------------------------------------
create or replace function public.best_offer(p_studio_id uuid, p_kind text, p_target text)
returns public.studio_offers
language sql stable security definer set search_path = public
as $$
  select o from public.studio_offers o
  where o.studio_id = p_studio_id and o.is_active and (o.ends_at is null or o.ends_at > now())
    and (o.applies_to = 'everything'
         or (p_kind = 'session' and (o.applies_to = 'sessions' or (o.applies_to = 'session_type' and o.target_id = p_target)))
         or (p_kind = 'add_on' and (o.applies_to = 'add_ons' or (o.applies_to = 'add_on' and o.target_id = p_target))))
  order by o.percent_off desc, o.created_at
  limit 1;
$$;
revoke execute on function public.best_offer(uuid, text, text) from public, anon, authenticated;

-- Returns { price, add_ons, promo_code_id }. Raises for unknown session types / bad codes.
create or replace function public.price_booking(
  p_studio public.studios, p_session_type_id text, p_hours integer, p_add_ons jsonb, p_promo_code text, p_artist uuid
) returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_type jsonb := (select t from jsonb_array_elements(p_studio.session_types) as t where t ->> 'id' = p_session_type_id limit 1);
  v_rate integer;
  v_session integer;
  v_offer public.studio_offers;
  v_discounts jsonb := '[]'::jsonb;
  v_offer_discount integer := 0;
  v_line_discount integer;
  v_addons_amount integer := 0;
  v_booked jsonb := '[]'::jsonb;
  v_addon jsonb;
  v_qty integer;
  v_amount integer;
  v_original integer;
  v_code public.promo_codes;
  v_promo integer := 0;
  v_subtotal integer;
  v_commission integer;
  v_fee integer := 0;
  v_total integer;
  v_deposit_pct integer;
  v_deposit integer;
  v_due_now integer;
begin
  if v_type is null then raise exception 'Unknown session type.'; end if;
  v_rate := (v_type ->> 'hourly_rate')::int;
  v_session := v_rate * p_hours;

  v_offer := public.best_offer(p_studio.id, 'session', p_session_type_id);
  if v_offer.id is not null then
    v_line_discount := public.pct(v_session, v_offer.percent_off);
    v_offer_discount := v_offer_discount + v_line_discount;
    v_discounts := v_discounts || jsonb_build_object('label', v_offer.title, 'percent', v_offer.percent_off, 'amount', v_line_discount, 'kind', 'offer');
  end if;

  -- Add-ons: [{ "id": "...", "quantity": n }]
  for v_addon in select a from jsonb_array_elements(coalesce(p_studio.add_ons, '[]'::jsonb)) as a loop
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
    v_offer := public.best_offer(p_studio.id, 'add_on', v_addon ->> 'id');
    if v_offer.id is not null and v_amount > 0 then
      v_line_discount := public.pct(v_amount, v_offer.percent_off);
      v_offer_discount := v_offer_discount + v_line_discount;
      v_discounts := v_discounts || jsonb_build_object('label', v_offer.title, 'percent', v_offer.percent_off, 'amount', v_line_discount, 'kind', 'offer');
    end if;
  end loop;

  v_original := v_session + v_addons_amount;
  v_subtotal := v_original - v_offer_discount;

  if nullif(btrim(coalesce(p_promo_code, '')), '') is not null then
    v_code := public.find_promo_code(p_studio.id, p_promo_code, p_artist);
    v_promo := public.pct(v_subtotal, v_code.percent_off);
    v_discounts := v_discounts || jsonb_build_object('label', v_code.code, 'percent', v_code.percent_off, 'amount', v_promo,
                                                     'kind', case when v_code.studio_id is null then 'easysesh_code' else 'studio_code' end);
    if v_code.studio_id is not null then
      v_subtotal := v_subtotal - v_promo;   -- the studio gives the discount
    else
      v_fee := -v_promo;                    -- EasySesh gives the discount
    end if;
  end if;

  v_total := v_subtotal + v_fee;
  v_commission := public.pct(v_subtotal, coalesce(p_studio.platform_fee_percent, 10));
  v_deposit_pct := least(greatest(coalesce((p_studio.booking_policy ->> 'deposit_percent')::int, 0), 0), 100);
  v_deposit := case when v_deposit_pct > 0 and v_deposit_pct < 100 then public.pct(v_total, v_deposit_pct) else 0 end;
  v_due_now := case when v_deposit > 0 then v_deposit else v_total end;

  return jsonb_build_object(
    'promo_code_id', v_code.id,
    'add_ons', v_booked,
    'price', jsonb_build_object(
      'currency', p_studio.currency, 'hourly_rate', v_rate, 'hours', p_hours,
      'session_amount', v_session, 'add_ons_amount', v_addons_amount,
      'original_subtotal', v_original, 'offer_discount', v_offer_discount,
      'promo_discount', v_promo, 'promo_code', v_code.code, 'discounts', v_discounts,
      'subtotal', v_subtotal, 'service_fee', v_fee, 'total', v_total, 'deposit_amount', v_deposit,
      'due_now', v_due_now, 'due_later', v_total - v_due_now,
      'studio_commission', v_commission, 'studio_payout', v_subtotal - v_commission));
end;
$$;
revoke execute on function public.price_booking(public.studios, text, integer, jsonb, text, uuid) from public, anon, authenticated;

-- Price summary on the booking page (same numbers as the booking will get).
create or replace function public.quote_booking(
  p_studio_id uuid, p_session_type_id text, p_hours integer, p_add_ons jsonb default '[]'::jsonb, p_promo_code text default null
) returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.id = p_studio_id);
begin
  if v_studio.id is null or v_studio.status <> 'approved' or not v_studio.is_active then raise exception 'not_found'; end if;
  if p_hours is null or p_hours < 1 or p_hours > 12 then raise exception 'Sessions can be at most 12 hours.'; end if;
  if p_promo_code is not null and auth.uid() is null then raise exception 'Please sign in to continue.'; end if;
  return public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid()) -> 'price';
end;
$$;
grant execute on function public.quote_booking(uuid, text, integer, jsonb, text) to anon, authenticated;

-- Booking with an optional promo code. (create_booking keeps its signature for older app builds.)
create or replace function public.book_session(
  p_studio_id uuid,
  p_session_type_id text,
  p_starts_at timestamptz,
  p_hours integer,
  p_add_ons jsonb default '[]'::jsonb,
  p_notes text default '',
  p_promo_code text default null
) returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  v_studio public.studios;
  v_type jsonb;
  v_min integer;
  v_priced jsonb;
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
  v_min := coalesce((v_type ->> 'minimum_hours')::int, 1);
  if p_hours is null or p_hours < v_min then
    raise exception 'Minimum % hours for %.', v_min, v_type ->> 'name';
  end if;
  if p_hours > 12 then raise exception 'Sessions can be at most 12 hours.'; end if;

  perform public.check_booking_slot(v_studio, p_starts_at, p_hours);
  v_priced := public.price_booking(v_studio, p_session_type_id, p_hours, p_add_ons, p_promo_code, auth.uid());

  v_reference := 'ES-' || upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
  v_artist_name := coalesce(nullif((select a.artist_name from public.artist_profiles a where a.id = auth.uid()), ''),
                            (select p.email from public.profiles p where p.id = auth.uid()));

  begin
    insert into public.bookings (id, reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name,
      starts_at, ends_at, hours, add_ons, price, notes, changed_by, promo_code_id)
    values (v_id, v_reference, auth.uid(), v_studio.id, v_artist_name, v_studio.name, p_session_type_id, v_type ->> 'name',
      p_starts_at, p_starts_at + make_interval(hours => p_hours), p_hours, v_priced -> 'add_ons', v_priced -> 'price',
      left(coalesce(p_notes, ''), 1000), auth.uid(), (v_priced ->> 'promo_code_id')::uuid);
  exception when exclusion_violation then
    raise exception 'slot_unavailable' using errcode = '23P01';
  end;
  return (select b from public.bookings b where b.id = v_id);
end;
$$;
revoke execute on function public.book_session(uuid, text, timestamptz, integer, jsonb, text, text) from public, anon;
grant execute on function public.book_session(uuid, text, timestamptz, integer, jsonb, text, text) to authenticated;

create or replace function public.create_booking(
  p_studio_id uuid,
  p_session_type_id text,
  p_starts_at timestamptz,
  p_hours integer,
  p_add_ons jsonb default '[]'::jsonb,
  p_notes text default ''
) returns public.bookings
language sql security definer set search_path = public
as $$
  select public.book_session(p_studio_id, p_session_type_id, p_starts_at, p_hours, p_add_ons, p_notes, null);
$$;

-- Cash: the studio collected the discounted total, so an EasySesh code lowers (or credits) the fee it owes.
create or replace function public.on_cash_booking_completed()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new.payment_method = 'cash' then
    insert into public.studio_fee_ledger (studio_id, booking_id, kind, amount, currency, note)
    values (new.studio_id, new.id, 'cash_commission',
            (new.price ->> 'studio_commission')::int + coalesce((new.price ->> 'service_fee')::int, 0), new.price ->> 'currency',
            'Platform fee for cash booking ' || new.reference)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
