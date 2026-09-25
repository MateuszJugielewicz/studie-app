-- EasySesh: admin badge (cosmetic), admin-only studio tags and paid promotions.

-- ---------------------------------------------------------------------------
-- Columns. All three are set by admins/the server only (see the guards below).
-- ---------------------------------------------------------------------------
alter table public.artist_profiles
  add column if not exists has_admin_badge boolean not null default false;

alter table public.studios
  add column if not exists has_admin_badge boolean not null default false,
  add column if not exists admin_tags text[] not null default '{}',
  add column if not exists promoted_until timestamptz;

create index if not exists studios_promoted_idx on public.studios (promoted_until) where promoted_until is not null;

-- ---------------------------------------------------------------------------
-- Guards: owners/artists can't give themselves a badge, tags or a promotion.
-- ---------------------------------------------------------------------------
create or replace function public.guard_artist_profiles()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.is_verified := false;
      new.has_admin_badge := false;
    else
      new.is_verified := old.is_verified;
      new.has_admin_badge := old.has_admin_badge;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.guard_studio_extras()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.has_admin_badge := false;
      new.admin_tags := '{}';
      new.promoted_until := null;
    else
      new.has_admin_badge := old.has_admin_badge;
      new.admin_tags := old.admin_tags;
      new.promoted_until := old.promoted_until;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists guard_studio_extras on public.studios;
create trigger guard_studio_extras before insert or update on public.studios
  for each row execute function public.guard_studio_extras();

-- ---------------------------------------------------------------------------
-- Promotions
-- ---------------------------------------------------------------------------
create table if not exists public.studio_promotions (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  package text not null check (package in ('week', 'two_weeks', 'month', 'custom')),
  days integer not null check (days between 1 and 365),
  amount integer not null default 0,
  currency text not null default 'EUR',
  status text not null default 'pending' check (status in ('pending', 'active', 'expired', 'cancelled')),
  source text not null default 'purchase' check (source in ('purchase', 'admin')),
  payment_intent_id text unique,
  starts_at timestamptz,
  ends_at timestamptz,
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index if not exists studio_promotions_studio_idx on public.studio_promotions (studio_id, created_at desc);

alter table public.studio_promotions enable row level security;
drop policy if exists "studio_promotions: owner or admin read" on public.studio_promotions;
create policy "studio_promotions: owner or admin read" on public.studio_promotions for select
  using (public.owns_studio(studio_id) or public.is_admin());

-- Starts a paid or granted promotion: it runs after any promotion that is still active.
create or replace function public.activate_promotion(p_promotion_id uuid)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_studio uuid := (select p.studio_id from public.studio_promotions p where p.id = p_promotion_id);
  v_days integer := (select p.days from public.studio_promotions p where p.id = p_promotion_id);
  v_status text := (select p.status from public.studio_promotions p where p.id = p_promotion_id);
  v_start timestamptz;
begin
  if v_studio is null then raise exception 'not_found'; end if;
  if v_status = 'active' then
    return (select p from public.studio_promotions p where p.id = p_promotion_id);
  end if;
  v_start := greatest(now(), coalesce((select s.promoted_until from public.studios s where s.id = v_studio), now()));
  update public.studio_promotions
  set status = 'active', starts_at = v_start, ends_at = v_start + make_interval(days => v_days)
  where id = p_promotion_id;
  update public.studios
  set promoted_until = v_start + make_interval(days => v_days)
  where id = v_studio;
  perform public.notify((select s.owner_id from public.studios s where s.id = v_studio), 'system',
    'Your studio is promoted',
    'Your studio shows at the top of search with a Promoted tag until ' ||
      to_char(v_start + make_interval(days => v_days), 'DD Mon YYYY') || '.',
    null, null, v_studio);
  return (select p from public.studio_promotions p where p.id = p_promotion_id);
end;
$$;
revoke execute on function public.activate_promotion from public, anon, authenticated;

-- Marks finished promotions as expired (called by the housekeeping job).
create or replace function public.expire_promotions()
returns integer
language sql security definer set search_path = public
as $$
  with done as (
    update public.studio_promotions set status = 'expired'
    where status = 'active' and ends_at <= now()
    returning 1
  )
  select count(*)::int from done;
$$;
revoke execute on function public.expire_promotions from public, anon, authenticated;

-- Prices per package and currency (minor units). The app shows the same table (Promotions.swift).
create or replace function public.promotion_price(p_package text, p_currency text)
returns integer language sql immutable as $$
  select case upper(coalesce(p_currency, 'EUR'))
    when 'DKK' then case p_package when 'week' then 14900 when 'two_weeks' then 26900 when 'month' then 44900 end
    when 'SEK' then case p_package when 'week' then 21900 when 'two_weeks' then 39900 when 'month' then 65900 end
    when 'NOK' then case p_package when 'week' then 21900 when 'two_weeks' then 39900 when 'month' then 65900 end
    when 'GBP' then case p_package when 'week' then 1600 when 'two_weeks' then 2900 when 'month' then 4900 end
    when 'USD' then case p_package when 'week' then 2100 when 'two_weeks' then 3900 when 'month' then 6500 end
    when 'PLN' then case p_package when 'week' then 8900 when 'two_weeks' then 15900 when 'month' then 25900 end
    else case p_package when 'week' then 1900 when 'two_weeks' then 3500 when 'month' then 5900 end
  end;
$$;

create or replace function public.promotion_days(p_package text)
returns integer language sql immutable as $$
  select case p_package when 'week' then 7 when 'two_weeks' then 14 when 'month' then 30 end;
$$;

-- Studio orders a promotion. It starts when paid in the app (Stripe) or when an admin activates it
-- after payment by other means.
create or replace function public.request_promotion(p_package text)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.owner_id = auth.uid() limit 1);
  v_id uuid := gen_random_uuid();
begin
  if v_studio.id is null or not public.owns_approved_studio(v_studio.id) then
    raise exception 'Only approved studios can be promoted.';
  end if;
  if public.promotion_days(p_package) is null then raise exception 'Unknown promotion package.'; end if;
  -- Only one open request at a time: replace an unpaid one.
  update public.studio_promotions set status = 'cancelled'
  where studio_id = v_studio.id and status = 'pending' and source = 'purchase';
  insert into public.studio_promotions (id, studio_id, package, days, amount, currency, source, created_by)
  values (v_id, v_studio.id, p_package, public.promotion_days(p_package),
          public.promotion_price(p_package, v_studio.currency), upper(v_studio.currency), 'purchase', auth.uid());
  return (select p from public.studio_promotions p where p.id = v_id);
end;
$$;

-- Studio withdraws an unpaid request.
create or replace function public.cancel_promotion_request(p_promotion_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.studio_promotions p set status = 'cancelled'
  where p.id = p_promotion_id and p.status = 'pending' and (public.owns_studio(p.studio_id) or public.is_admin());
end;
$$;

-- Admin starts a requested promotion after the studio paid outside the app.
create or replace function public.admin_activate_promotion(p_promotion_id uuid)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  if not exists (select 1 from public.studio_promotions p where p.id = p_promotion_id and p.status = 'pending') then
    raise exception 'This request is not pending.';
  end if;
  return public.activate_promotion(p_promotion_id);
end;
$$;

-- Admin view of promotions with the studio name.
drop view if exists public.admin_promotions;
create view public.admin_promotions with (security_invoker = true) as
select p.*, s.name as studio_name, s.promoted_until
from public.studio_promotions p join public.studios s on s.id = p.studio_id;

-- ---------------------------------------------------------------------------
-- Admin tools
-- ---------------------------------------------------------------------------
-- Cosmetic "EasySesh team" badge on the artist profile and the user's studio. No extra rights.
create or replace function public.admin_set_admin_badge(p_user_id uuid, p_on boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  update public.artist_profiles set has_admin_badge = p_on where id = p_user_id;
  update public.studios set has_admin_badge = p_on where owner_id = p_user_id;
end;
$$;

-- Special tags only admins can put on a studio (e.g. "Staff pick").
create or replace function public.admin_set_studio_tags(p_studio_id uuid, p_tags text[])
returns public.studios
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  update public.studios
  set admin_tags = coalesce((
    select array_agg(distinct left(btrim(t), 30)) from unnest(p_tags) as t where btrim(t) <> ''
  ), '{}')
  where id = p_studio_id;
  if not found then raise exception 'not_found'; end if;
  return (select s from public.studios s where s.id = p_studio_id);
end;
$$;

-- Free promotion granted by an admin (e.g. launch offer or compensation).
create or replace function public.admin_grant_promotion(p_studio_id uuid, p_days integer, p_note text default null)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  perform public.require_admin();
  if not exists (select 1 from public.studios s where s.id = p_studio_id and s.status = 'approved') then
    raise exception 'Only approved studios can be promoted.';
  end if;
  insert into public.studio_promotions (id, studio_id, package, days, source, note, created_by, currency)
  select v_id, p_studio_id, 'custom', p_days, 'admin', p_note, auth.uid(), s.currency
  from public.studios s where s.id = p_studio_id;
  return public.activate_promotion(v_id);
end;
$$;

-- Ends a studio's promotion now (admin).
create or replace function public.admin_end_promotion(p_studio_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  update public.studio_promotions set status = 'cancelled', ends_at = now()
  where studio_id = p_studio_id and status = 'active';
  update public.studios set promoted_until = null where id = p_studio_id;
end;
$$;

-- Admin user list shows the badge.
drop view if exists public.admin_users;
create view public.admin_users with (security_invoker = true) as
select p.id, p.email, p.role, p.status, p.status_reason, p.is_verified, p.created_at,
  a.artist_name, a.city as artist_city,
  s.id as studio_id, s.name as studio_name,
  coalesce(a.has_admin_badge, s.has_admin_badge, false) as has_admin_badge,
  (select count(*) from public.bookings b where b.artist_id = p.id) as booking_count
from public.profiles p
left join public.artist_profiles a on a.id = p.id
left join public.studios s on s.owner_id = p.id;

-- Artist search (studios starting a chat) shows the badge too. Return type changes, so drop first.
drop function if exists public.search_artists(text);
create or replace function public.search_artists(p_query text)
returns table (id uuid, artist_name text, city text, genres text[], avatar_url text, is_verified boolean, has_booked boolean, has_admin_badge boolean)
language plpgsql stable security definer set search_path = public
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  my_studio uuid := (select s.id from public.studios s where s.owner_id = auth.uid() limit 1);
begin
  if my_studio is null or not public.owns_approved_studio(my_studio) then
    raise exception 'Only approved studios can message artists.' using errcode = '42501';
  end if;
  return query
    select a.id, a.artist_name, a.city, a.genres, a.avatar_url, a.is_verified,
      exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio) as has_booked,
      a.has_admin_badge
    from public.artist_profiles a
    join public.profiles p on p.id = a.id
    where p.status = 'active' and p.role = 'artist' and a.artist_name <> ''
      and (char_length(q) < 2 and exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio)
           or char_length(q) >= 2 and (a.artist_name ilike '%' || q || '%' or a.city ilike q || '%'))
    order by 7 desc, 6 desc, 2
    limit 30;
end;
$$;

-- Promotions end on their own (promoted_until); this keeps the history tidy.
select cron.schedule('easysesh-expire-promotions', '23 * * * *', $$select public.expire_promotions()$$);
