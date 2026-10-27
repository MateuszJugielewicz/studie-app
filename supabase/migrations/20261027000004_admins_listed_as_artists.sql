-- Team members (admin accounts) who are artists too, e.g. with the team badge, were left out of the
-- studios' artist search and "Find artists" because those only took role = 'artist'. An admin with a
-- filled-in artist profile now shows up there, and studios can message or connect them like any artist.

do $$
declare f text; d text;
begin
  foreach f in array array['search_artists', 'discover_artists'] loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = f;
    d := replace(d, 'where p.status = ''active'' and p.role = ''artist'' and a.artist_name <> ''''',
      'where p.status = ''active'' and p.role in (''artist'', ''admin'') and a.artist_name <> ''''');
    execute d;
  end loop;
  foreach f in array array['studio_start_conversation', 'request_studio_artist_link'] loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = f;
    d := replace(d, 'p.role = ''artist'' and p.status = ''active''',
      'p.status = ''active'' and (p.role = ''artist'' or p.role = ''admin'' and exists (select 1 from public.artist_profiles a2 where a2.id = p.id and a2.artist_name <> ''''))');
    execute d;
  end loop;
end $$;
