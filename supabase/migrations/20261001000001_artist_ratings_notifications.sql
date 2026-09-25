-- EasySesh: studios rate artists after a completed session; users can delete their notifications.

-- Notifications: swipe to delete.
drop policy if exists "notifications: own delete" on public.notifications;
create policy "notifications: own delete" on public.notifications for delete using (user_id = auth.uid());

-- Artist ratings (given by studios).
alter table public.artist_profiles
  add column if not exists rating_average numeric(3, 2) not null default 0,
  add column if not exists review_count integer not null default 0;

create table if not exists public.artist_reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id) on delete cascade,
  studio_id uuid not null references public.studios (id) on delete cascade,
  artist_id uuid not null references public.profiles (id) on delete cascade,
  studio_name text not null,
  rating smallint not null check (rating between 1 and 5),
  text text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists artist_reviews_artist_idx on public.artist_reviews (artist_id, created_at desc);

alter table public.artist_reviews enable row level security;
drop policy if exists "artist_reviews: read" on public.artist_reviews;
create policy "artist_reviews: read" on public.artist_reviews for select to authenticated using (true);

-- Artists can't edit their own rating numbers.
create or replace function public.guard_artist_profiles()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.is_verified := false;
      new.has_admin_badge := false;
      new.rating_average := 0;
      new.review_count := 0;
    else
      new.is_verified := old.is_verified;
      new.has_admin_badge := old.has_admin_badge;
      new.rating_average := old.rating_average;
      new.review_count := old.review_count;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Studio rates the artist of one of its completed bookings (can update it later).
create or replace function public.review_artist(p_booking_id uuid, p_rating integer, p_text text default '')
returns public.artist_reviews
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings := (select b from public.bookings b where b.id = p_booking_id);
  v_is_new boolean;
begin
  if v_booking.id is null then raise exception 'not_found'; end if;
  if not public.owns_approved_studio(v_booking.studio_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if v_booking.status <> 'completed' then raise exception 'You can rate the artist after the session is completed.'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Pick 1 to 5 stars.'; end if;
  v_is_new := not exists (select 1 from public.artist_reviews r where r.booking_id = p_booking_id);

  insert into public.artist_reviews (booking_id, studio_id, artist_id, studio_name, rating, text)
  values (v_booking.id, v_booking.studio_id, v_booking.artist_id, v_booking.studio_name, p_rating, left(btrim(coalesce(p_text, '')), 1000))
  on conflict (booking_id) do update set rating = excluded.rating, text = excluded.text, updated_at = now();

  -- Ratings removed after a dispute (is_hidden, added later) don't count.
  update public.artist_profiles a set
    rating_average = coalesce((select round(avg(r.rating)::numeric, 2) from public.artist_reviews r where r.artist_id = a.id and not r.is_hidden), 0),
    review_count = (select count(*) from public.artist_reviews r where r.artist_id = a.id and not r.is_hidden)
  where a.id = v_booking.artist_id;

  if v_is_new then
    perform public.notify(v_booking.artist_id, 'new_review', v_booking.studio_name || ' rated you',
      repeat('★', p_rating) || repeat('☆', 5 - p_rating), v_booking.id, null, v_booking.studio_id);
  end if;
  return (select r from public.artist_reviews r where r.booking_id = p_booking_id);
end;
$$;
