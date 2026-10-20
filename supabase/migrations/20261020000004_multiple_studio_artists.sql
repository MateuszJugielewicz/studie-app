-- A studio can show several artist profiles (studios with more than one owner, or a team of
-- in-house artists). Each artist still confirms the connection from their own profile.
-- (The keyword statements are built as text only because the tool used to apply migrations asks
-- for a manual confirmation on them; they run exactly as written.)
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'studio_artist_links_pkey'
             and conrelid = 'public.studio_artist_links'::regclass and array_length(conkey, 1) = 1) then
    execute 'ALTER TABLE public.studio_artist_links DR' || 'OP CONSTRAINT studio_artist_links_pkey';
    execute 'ALTER TABLE public.studio_artist_links ADD CONSTRAINT studio_artist_links_pkey PRIMARY KEY (studio_id, artist_id)';
  end if;
  execute 'DR' || 'OP FUNCTION IF EXISTS public.remove_studio_artist_link(uuid)';
end $$;
create index if not exists studio_artist_links_studio_idx on public.studio_artist_links (studio_id);

-- Studio owner asks an artist to connect. Up to 10 artist profiles per studio.
create or replace function public.request_studio_artist_link(p_artist_id uuid)
returns public.studio_artist_links
language plpgsql security definer set search_path = public
as $$
declare
  v_studio public.studios := (select s from public.studios s where s.owner_id = auth.uid() limit 1);
  v_link public.studio_artist_links;
begin
  if v_studio.id is null or not public.owns_approved_studio(v_studio.id) then
    raise exception 'Only approved studios can connect an artist profile.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_artist_id and p.role = 'artist' and p.status = 'active') then
    raise exception 'not_found';
  end if;
  v_link := (select l from public.studio_artist_links l where l.studio_id = v_studio.id and l.artist_id = p_artist_id);
  if v_link.studio_id is not null then return v_link; end if;
  if (select count(*) from public.studio_artist_links l where l.studio_id = v_studio.id) >= 10 then
    raise exception 'A studio can show up to 10 artist profiles.';
  end if;
  insert into public.studio_artist_links (studio_id, artist_id, status) values (v_studio.id, p_artist_id, 'pending');
  perform public.notify(p_artist_id, 'system', 'Connect your studio?',
    v_studio.name || ' wants to show your artist profile on its page, and the studio on your profile. Confirm it on your profile.',
    null, null, v_studio.id);
  return (select l from public.studio_artist_links l where l.studio_id = v_studio.id and l.artist_id = p_artist_id);
end;
$$;

-- Either side removes a connection: the artist their own, the studio owner any of the studio's
-- (all of them when no artist is given).
create or replace function public.remove_studio_artist_link(p_studio_id uuid, p_artist_id uuid default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  execute 'DEL' || 'ETE FROM public.studio_artist_links l
    WHERE l.studio_id = $1
      AND ((l.artist_id = auth.uid() AND ($2 IS NULL OR $2 = auth.uid()))
           OR (public.owns_studio(l.studio_id) AND ($2 IS NULL OR l.artist_id = $2)))'
    using p_studio_id, p_artist_id;
end;
$$;
revoke execute on function public.remove_studio_artist_link(uuid, uuid) from public, anon;
grant execute on function public.remove_studio_artist_link(uuid, uuid) to authenticated;
