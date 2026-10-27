-- Team members can be artists too. Adding someone to the admin team turns their role into 'admin', which
-- took away everything artists do. An admin with a filled-in artist profile now counts as an artist:
-- they can book studios, message studios, post stories, buy promotions and credits, and apply for
-- verification. Admins without an artist profile (e.g. the owner's account) are unchanged.

create or replace function public.is_artist_account(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.status = 'active'
      and (p.role = 'artist'
           or p.role = 'admin' and exists (select 1 from public.artist_profiles a where a.id = p.id and a.artist_name <> ''))
  );
$$;
revoke execute on function public.is_artist_account(uuid) from public, anon;
grant execute on function public.is_artist_account(uuid) to authenticated;

do $$
declare
  d text;
  -- {function, text to find, replacement}
  patches text[][] := array[
    ['book_session',
     'select 1 from public.profiles p where p.id = auth.uid() and p.role = ''artist'' and p.status = ''active''',
     'select 1 where public.is_artist_account(auth.uid())'],
    ['get_or_create_conversation',
     'if me.role = ''artist'' then',
     'if me.role = ''artist'' or me.role = ''admin'' and public.is_artist_account(me.id) then'],
    ['post_story',
     'v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = ''active'');',
     'v_role public.user_role := (select case when p.role = ''admin'' and public.is_artist_account(p.id) then ''artist''::public.user_role else p.role end from public.profiles p where p.id = auth.uid() and p.status = ''active'');'],
    ['request_promotion',
     'v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = ''active'');',
     'v_role public.user_role := (select case when p.role = ''admin'' and public.is_artist_account(p.id) then ''artist''::public.user_role else p.role end from public.profiles p where p.id = auth.uid() and p.status = ''active'');'],
    ['request_verification',
     'v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = ''active'');',
     'v_role public.user_role := (select case when p.role = ''admin'' and public.is_artist_account(p.id) then ''artist''::public.user_role else p.role end from public.profiles p where p.id = auth.uid() and p.status = ''active'');'],
    ['admin_grant_artist_promotion',
     'where a.id = p_artist_id and p.role = ''artist'' and a.artist_name <> '''') then',
     'where a.id = p_artist_id and p.role in (''artist'', ''admin'') and a.artist_name <> '''') then'],
    ['admin_adjust_credits',
     'p.role in (''artist'', ''studio_owner'')',
     '(p.role = ''studio_owner'' or public.is_artist_account(p.id))']
  ];
  i int;
begin
  for i in 1 .. array_length(patches, 1) loop
    select replace(pg_get_functiondef(p.oid), E'\r', '') into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = patches[i][1];
    if d is null or position(patches[i][2] in d) = 0 then raise exception 'Pattern not found in %', patches[i][1]; end if;
    execute replace(d, patches[i][2], patches[i][3]);
  end loop;
end $$;
