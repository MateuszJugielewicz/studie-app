-- Studios find artists the way artists find studios: a browsable list (search, genre and city
-- filters, sorting) instead of only a name search. Promoted artists come first, with a Promoted tag.
-- Only approved studios can browse, like messaging artists; people who blocked each other are left out.
create or replace function public.discover_artists()
returns table (
  id uuid, artist_name text, city text, genres text[], avatar_url text, bio text, is_verified boolean,
  has_admin_badge boolean, rating_average double precision, review_count integer, session_count integer,
  is_promoted boolean, has_booked boolean, joined_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare
  my_studio uuid := (select s.id from public.studios s where s.owner_id = auth.uid() limit 1);
begin
  if my_studio is null or not public.owns_approved_studio(my_studio) then
    raise exception 'Only approved studios can look for artists.' using errcode = '42501';
  end if;
  return query
    select a.id, a.artist_name, a.city, a.genres, a.avatar_url, left(a.bio, 280), a.is_verified,
      coalesce(a.has_admin_badge, false), coalesce(a.rating_average, 0)::double precision, coalesce(a.review_count, 0),
      (select count(*)::int from public.bookings b where b.artist_id = a.id and b.status = 'completed'),
      coalesce(a.promoted_until > now(), false),
      exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio),
      p.created_at
    from public.artist_profiles a
    join public.profiles p on p.id = a.id
    where p.status = 'active' and p.role = 'artist' and a.artist_name <> '' and a.id <> auth.uid()
      and not public.is_blocked_between(auth.uid(), a.id)
    order by 12 desc, 9 desc, 11 desc, 2
    limit 1000;
end;
$$;
revoke execute on function public.discover_artists() from public, anon;
grant execute on function public.discover_artists() to authenticated;
