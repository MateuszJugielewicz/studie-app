-- EasySesh: connect a studio to an artist profile (e.g. an artist who also runs a studio).
-- The studio asks, the artist confirms; both profiles then show the connection.

create table if not exists public.studio_artist_links (
  studio_id uuid primary key references public.studios (id) on delete cascade,
  artist_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now()
);
create index if not exists studio_artist_links_artist_idx on public.studio_artist_links (artist_id);

alter table public.studio_artist_links enable row level security;
drop policy if exists "studio_artist_links: read" on public.studio_artist_links;
create policy "studio_artist_links: read" on public.studio_artist_links for select to authenticated
  using (status = 'accepted' or artist_id = auth.uid() or public.owns_studio(studio_id) or public.is_admin());

-- Studio owner asks an artist to connect profiles.
create or replace function public.request_studio_artist_link(p_artist_id uuid)
returns public.studio_artist_links
language plpgsql security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.owner_id = auth.uid() limit 1);
begin
  if v_studio.id is null or not public.owns_approved_studio(v_studio.id) then
    raise exception 'Only approved studios can connect an artist profile.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_artist_id and p.role = 'artist' and p.status = 'active') then
    raise exception 'not_found';
  end if;
  insert into public.studio_artist_links (studio_id, artist_id, status)
  values (v_studio.id, p_artist_id, 'pending')
  on conflict (studio_id) do update set artist_id = excluded.artist_id, status = 'pending', created_at = now();
  perform public.notify(p_artist_id, 'system', 'Connect your studio?',
    v_studio.name || ' wants to show your artist profile on its page, and the studio on your profile. Confirm it on your profile.',
    null, null, v_studio.id);
  return (select l from public.studio_artist_links l where l.studio_id = v_studio.id);
end;
$$;

-- Artist confirms or declines a connection request.
create or replace function public.respond_studio_artist_link(p_studio_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_accept then
    update public.studio_artist_links set status = 'accepted' where studio_id = p_studio_id and artist_id = auth.uid();
  else
    delete from public.studio_artist_links where studio_id = p_studio_id and artist_id = auth.uid();
  end if;
  if not found and p_accept then raise exception 'not_found'; end if;
end;
$$;

-- Either side removes the connection.
create or replace function public.remove_studio_artist_link(p_studio_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  delete from public.studio_artist_links l
  where l.studio_id = p_studio_id and (l.artist_id = auth.uid() or public.owns_studio(l.studio_id));
end;
$$;
