-- Promotions for artists too. A promoted artist is shown first (with a Promoted tag) when studios
-- search for artists to message. Studios and artists buy promotions on the website (Stripe, via the
-- promotion-payment function); the apps only show the status, as App Store / Play rules require.

alter table public.studio_promotions add column if not exists artist_id uuid references public.profiles (id) on delete cascade;
alter table public.studio_promotions alter column studio_id drop not null;
alter table public.studio_promotions drop constraint if exists studio_promotions_one_target;
alter table public.studio_promotions add constraint studio_promotions_one_target
  check ((studio_id is null) <> (artist_id is null)) not valid;
create index if not exists studio_promotions_artist on public.studio_promotions (artist_id) where artist_id is not null;

alter table public.artist_profiles add column if not exists promoted_until timestamptz;

drop policy if exists "studio_promotions: owner or admin read" on public.studio_promotions;
create policy "studio_promotions: owner or admin read" on public.studio_promotions for select
  using ((studio_id is not null and public.owns_studio(studio_id)) or artist_id = auth.uid() or public.is_admin());

-- Artists can't promote themselves for free.
create or replace function public.guard_artist_profiles()
returns trigger
language plpgsql set search_path = public, extensions
as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.is_verified := false;
      new.has_admin_badge := false;
      new.rating_average := 0;
      new.review_count := 0;
      new.promoted_until := null;
    else
      new.is_verified := old.is_verified;
      new.has_admin_badge := old.has_admin_badge;
      new.rating_average := old.rating_average;
      new.review_count := old.review_count;
      new.promoted_until := old.promoted_until;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Order a promotion: approved studios for their studio, artists for their artist profile.
-- It starts when paid (promotion-payment / stripe-webhook) or when an admin activates it.
create or replace function public.request_promotion(p_package text)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = 'active');
  v_studio public.studios := (select s from public.studios s where s.owner_id = auth.uid() limit 1);
  v_id uuid := gen_random_uuid();
begin
  if public.promotion_days(p_package) is null then raise exception 'Unknown promotion package.'; end if;
  if v_role = 'artist' then
    if not exists (select 1 from public.artist_profiles a where a.id = auth.uid() and a.artist_name <> '') then
      raise exception 'Finish your artist profile first.';
    end if;
    update public.studio_promotions set status = 'cancelled'
    where artist_id = auth.uid() and status = 'pending' and source = 'purchase';
    insert into public.studio_promotions (id, artist_id, package, days, amount, currency, source, created_by)
    values (v_id, auth.uid(), p_package, public.promotion_days(p_package),
            public.promotion_price(p_package, 'EUR'), 'EUR', 'purchase', auth.uid());
  else
    if v_studio.id is null or not public.owns_approved_studio(v_studio.id) then
      raise exception 'Only approved studios can be promoted.';
    end if;
    update public.studio_promotions set status = 'cancelled'
    where studio_id = v_studio.id and status = 'pending' and source = 'purchase';
    insert into public.studio_promotions (id, studio_id, package, days, amount, currency, source, created_by)
    values (v_id, v_studio.id, p_package, public.promotion_days(p_package),
            public.promotion_price(p_package, v_studio.currency), upper(v_studio.currency), 'purchase', auth.uid());
  end if;
  return (select p from public.studio_promotions p where p.id = v_id);
end;
$$;

create or replace function public.cancel_promotion_request(p_promotion_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.studio_promotions p set status = 'cancelled'
  where p.id = p_promotion_id and p.status = 'pending'
    and ((p.studio_id is not null and public.owns_studio(p.studio_id)) or p.artist_id = auth.uid() or public.is_admin());
end;
$$;

create or replace function public.activate_promotion(p_promotion_id uuid)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_promo public.studio_promotions := (select p from public.studio_promotions p where p.id = p_promotion_id);
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_promo.id is null then raise exception 'not_found'; end if;
  if v_promo.status = 'active' then return v_promo; end if;
  if v_promo.artist_id is not null then
    v_start := greatest(now(), coalesce((select a.promoted_until from public.artist_profiles a where a.id = v_promo.artist_id), now()));
    v_end := v_start + make_interval(days => v_promo.days);
    update public.studio_promotions set status = 'active', starts_at = v_start, ends_at = v_end where id = p_promotion_id;
    update public.artist_profiles set promoted_until = v_end where id = v_promo.artist_id;
    perform public.notify(v_promo.artist_id, 'system', 'Your artist profile is promoted',
      'Studios see you first, with a Promoted tag, when they look for artists until ' || to_char(v_end, 'DD Mon YYYY') || '.',
      null, null, null);
  else
    v_start := greatest(now(), coalesce((select s.promoted_until from public.studios s where s.id = v_promo.studio_id), now()));
    v_end := v_start + make_interval(days => v_promo.days);
    update public.studio_promotions set status = 'active', starts_at = v_start, ends_at = v_end where id = p_promotion_id;
    update public.studios set promoted_until = v_end where id = v_promo.studio_id;
    perform public.notify((select s.owner_id from public.studios s where s.id = v_promo.studio_id), 'system',
      'Your studio is promoted',
      'Your studio shows at the top of search with a Promoted tag until ' || to_char(v_end, 'DD Mon YYYY') || '.',
      null, null, v_promo.studio_id);
  end if;
  return (select p from public.studio_promotions p where p.id = p_promotion_id);
end;
$$;
revoke execute on function public.activate_promotion(uuid) from public, anon, authenticated;

-- Admin panel: artist promotions show with the artist's name.
create or replace view public.admin_promotions with (security_invoker = true) as
select p.id, p.studio_id, p.package, p.days, p.amount, p.currency, p.status, p.source, p.payment_intent_id,
       p.starts_at, p.ends_at, p.note, p.created_by, p.created_at,
       coalesce(s.name, a.artist_name || ' (artist)') as studio_name, coalesce(s.promoted_until, a.promoted_until) as promoted_until,
       p.artist_id
from public.studio_promotions p
left join public.studios s on s.id = p.studio_id
left join public.artist_profiles a on a.id = p.artist_id;

-- Promoted artists first (with is_promoted, for the tag) in the studios' artist search.
drop function if exists public.search_artists(text);
create function public.search_artists(p_query text)
returns table (id uuid, artist_name text, city text, genres text[], avatar_url text, is_verified boolean, has_booked boolean, has_admin_badge boolean, is_promoted boolean)
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
      a.has_admin_badge, coalesce(a.promoted_until > now(), false) as is_promoted
    from public.artist_profiles a
    join public.profiles p on p.id = a.id
    where p.status = 'active' and p.role = 'artist' and a.artist_name <> ''
      and (char_length(q) < 2 and exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio)
           or char_length(q) >= 2 and (a.artist_name ilike '%' || q || '%' or a.city ilike q || '%'))
    order by 9 desc, 7 desc, 6 desc, 2
    limit 30;
end;
$$;
revoke execute on function public.search_artists(text) from public, anon;
grant execute on function public.search_artists(text) to authenticated;

-- Admin: free promotion for an artist profile, and ending one now.
create or replace function public.admin_grant_artist_promotion(p_artist_id uuid, p_days integer, p_note text default null)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  perform public.require_admin();
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'Choose 1–365 days.'; end if;
  if not exists (select 1 from public.artist_profiles a join public.profiles p on p.id = a.id
                 where a.id = p_artist_id and p.role = 'artist' and a.artist_name <> '') then
    raise exception 'Only artists with a profile can be promoted.';
  end if;
  insert into public.studio_promotions (id, artist_id, package, days, source, note, created_by, currency)
  values (v_id, p_artist_id, 'custom', p_days, 'admin', p_note, auth.uid(), 'EUR');
  return public.activate_promotion(v_id);
end;
$$;

create or replace function public.admin_end_artist_promotion(p_artist_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  update public.studio_promotions set status = 'cancelled', ends_at = now()
  where artist_id = p_artist_id and status = 'active';
  update public.artist_profiles set promoted_until = null where id = p_artist_id;
end;
$$;
revoke execute on function public.admin_grant_artist_promotion(uuid, integer, text) from public, anon;
revoke execute on function public.admin_end_artist_promotion(uuid) from public, anon;
grant execute on function public.admin_grant_artist_promotion(uuid, integer, text) to authenticated;
grant execute on function public.admin_end_artist_promotion(uuid) to authenticated;
