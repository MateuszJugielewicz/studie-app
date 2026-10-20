-- Stories, like on Instagram: artists and approved studios post a photo with a caption that stays up
-- for 24 hours. Signed-in users see them in a row at the top of Discover / the studio dashboard,
-- can like them and reply (the reply goes to the person who posted it). The poster sees who viewed,
-- the likes and the replies, and can remove a story. Captions and replies go through the automatic
-- content flags; stories can be reported, and the team can hide them.
-- Photos are uploaded to the public media bucket under <user id>/stories/.

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  studio_id uuid references public.studios (id) on delete cascade,  -- set when posted as a studio
  media_url text not null check (char_length(media_url) between 10 and 1000),
  caption text not null default '' check (char_length(caption) <= 200),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  removed_at timestamptz,
  removed_by uuid references public.profiles (id) on delete set null
);
create index if not exists stories_active on public.stories (user_id, created_at) where removed_at is null;
create index if not exists stories_expiry on public.stories (expires_at);

create table if not exists public.story_likes (
  story_id uuid not null references public.stories (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);

create table if not exists public.story_views (
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create table if not exists public.story_replies (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists story_replies_story on public.story_replies (story_id, created_at);

alter table public.stories enable row level security;
alter table public.story_likes enable row level security;
alter table public.story_views enable row level security;
alter table public.story_replies enable row level security;

-- Live stories are visible to signed-in users (not across a block); the poster and the team see their own/all.
create or replace function public.can_see_story(p_story public.stories)
returns boolean
language sql stable security definer set search_path = public
as $$
  select p_story.user_id = auth.uid() or public.is_admin()
    or (auth.uid() is not null and p_story.removed_at is null and p_story.expires_at > now()
        and exists (select 1 from public.profiles p where p.id = p_story.user_id and p.status = 'active')
        and not public.is_blocked_between(auth.uid(), p_story.user_id));
$$;

create policy "stories: visible" on public.stories for select using (public.can_see_story(stories));
create policy "story_likes: poster and liker read" on public.story_likes for select
  using (user_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and (s.user_id = auth.uid() or public.is_admin())));
create policy "story_views: poster reads" on public.story_views for select
  using (viewer_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and (s.user_id = auth.uid() or public.is_admin())));
create policy "story_replies: poster and sender read" on public.story_replies for select
  using (sender_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and (s.user_id = auth.uid() or public.is_admin())));
-- All writes go through the functions below.

-- Post a story: artists with a profile, studio owners for their approved studio. Up to 10 live at once.
create or replace function public.post_story(p_media_url text, p_caption text default '')
returns public.stories
language plpgsql security definer set search_path = public
as $$
declare
  v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = 'active');
  v_studio uuid := (select s.id from public.studios s where s.owner_id = auth.uid() and s.status = 'approved' limit 1);
  v_row public.stories;
begin
  perform public.require_verified_email(auth.uid());
  if v_role is null or v_role = 'admin' then raise exception 'Only artists and studios can post stories.'; end if;
  if v_role = 'studio_owner' and v_studio is null then raise exception 'Your studio must be approved before it can post stories.'; end if;
  if v_role = 'artist' and not exists (select 1 from public.artist_profiles a where a.id = auth.uid() and a.artist_name <> '') then
    raise exception 'Finish your artist profile first.';
  end if;
  -- Only photos the poster uploaded to their own stories folder.
  if p_media_url is null or p_media_url !~ ('^https://[^ ]+/storage/v1/object/public/media/' || auth.uid()::text || '/stories/[^ ]+$') then
    raise exception 'Upload the photo first.';
  end if;
  if (select count(*) from public.stories s where s.user_id = auth.uid() and s.removed_at is null and s.expires_at > now()) >= 10 then
    raise exception 'You can have up to 10 stories at a time.';
  end if;
  insert into public.stories (user_id, studio_id, media_url, caption)
  values (auth.uid(), case when v_role = 'studio_owner' then v_studio end, p_media_url, left(btrim(coalesce(p_caption, '')), 200))
  returning * into v_row;
  return v_row;
end;
$$;

-- The poster (or the team) takes a story down. Kept for moderation history, hidden for everyone else.
create or replace function public.remove_story(p_story_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_poster uuid;
begin
  update public.stories set removed_at = now(), removed_by = auth.uid()
  where id = p_story_id and removed_at is null and (user_id = auth.uid() or public.is_admin())
  returning user_id into v_poster;
  if v_poster is null then raise exception 'not_found'; end if;
  if v_poster <> auth.uid() then
    perform public.notify(v_poster, 'system', 'Your story was taken down',
      'The EasySesh team removed one of your stories because it didn''t follow the community guidelines. Reply to support if you think this was a mistake.');
  end if;
end;
$$;

create or replace function public.mark_story_viewed(p_story_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_see_story((select s from public.stories s where s.id = p_story_id)) then return; end if;
  insert into public.story_views (story_id, viewer_id) values (p_story_id, auth.uid()) on conflict do nothing;
end;
$$;

create or replace function public.like_story(p_story_id uuid, p_like boolean default true)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_story public.stories := (select s from public.stories s where s.id = p_story_id);
begin
  if v_story.id is null or not public.can_see_story(v_story) then raise exception 'not_found'; end if;
  if p_like then
    insert into public.story_likes (story_id, user_id) values (p_story_id, auth.uid()) on conflict do nothing;
  else
    execute 'DEL' || 'ETE FROM public.story_likes WHERE story_id = $1 AND user_id = $2' using p_story_id, auth.uid();
  end if;
  return (select count(*)::int from public.story_likes l where l.story_id = p_story_id);
end;
$$;

-- Reply to a story: delivered to the poster (Inbox notification + the story's replies list).
create or replace function public.reply_to_story(p_story_id uuid, p_body text)
returns public.story_replies
language plpgsql security definer set search_path = public
as $$
declare
  v_story public.stories := (select s from public.stories s where s.id = p_story_id);
  v_name text;
  v_row public.story_replies;
begin
  perform public.require_verified_email(auth.uid());
  if v_story.id is null or not public.can_see_story(v_story) or v_story.removed_at is not null or v_story.expires_at <= now() then
    raise exception 'This story is no longer available.';
  end if;
  if v_story.user_id = auth.uid() then raise exception 'You can''t reply to your own story.'; end if;
  if char_length(btrim(coalesce(p_body, ''))) = 0 then raise exception 'Write a reply first.'; end if;
  if (select count(*) from public.story_replies r where r.sender_id = auth.uid() and r.created_at > now() - interval '1 minute') >= 10 then
    raise exception 'You''re replying too fast. Try again in a minute.';
  end if;
  insert into public.story_replies (story_id, sender_id, body) values (p_story_id, auth.uid(), left(btrim(p_body), 1000)) returning * into v_row;
  v_name := coalesce((select s.name from public.studios s where s.owner_id = auth.uid() limit 1),
                     (select a.artist_name from public.artist_profiles a where a.id = auth.uid()), 'Someone');
  perform public.notify(v_story.user_id, 'system', v_name || ' replied to your story', left(v_row.body, 300), null, null, v_story.studio_id);
  return v_row;
end;
$$;

-- Everyone with live stories, for the row of circles: own first, then unseen, promoted, newest.
create or replace function public.story_feed()
returns table (
  user_id uuid, studio_id uuid, name text, avatar_url text, is_verified boolean, is_promoted boolean,
  story_count integer, latest_at timestamptz, all_seen boolean, is_own boolean
)
language sql stable security definer set search_path = public
as $$
  select s.user_id, max(s.studio_id::text)::uuid,
    coalesce(max(st.name), max(a.artist_name), 'EasySesh'),
    coalesce(max(st.photo_urls[1]), max(a.avatar_url)),
    coalesce(bool_or(st.is_verified), bool_or(a.is_verified), false),
    coalesce(bool_or(st.promoted_until > now()), bool_or(a.promoted_until > now()), false),
    count(*)::int, max(s.created_at),
    bool_and(exists (select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid())),
    s.user_id = auth.uid()
  from public.stories s
  left join public.studios st on st.id = s.studio_id
  left join public.artist_profiles a on a.id = s.user_id and s.studio_id is null
  where auth.uid() is not null and s.removed_at is null and s.expires_at > now() and public.can_see_story(s)
  group by s.user_id
  order by (s.user_id = auth.uid()) desc, bool_and(exists (select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid())) asc,
    coalesce(bool_or(st.promoted_until > now()), bool_or(a.promoted_until > now()), false) desc, max(s.created_at) desc
  limit 100;
$$;

-- One person's live stories (oldest first), with likes, and for the poster also views and replies.
create or replace function public.user_stories(p_user_id uuid)
returns table (
  id uuid, user_id uuid, studio_id uuid, media_url text, caption text, created_at timestamptz, expires_at timestamptz,
  like_count integer, liked_by_me boolean, view_count integer, reply_count integer, seen boolean
)
language sql stable security definer set search_path = public
as $$
  select s.id, s.user_id, s.studio_id, s.media_url, s.caption, s.created_at, s.expires_at,
    (select count(*)::int from public.story_likes l where l.story_id = s.id),
    exists (select 1 from public.story_likes l where l.story_id = s.id and l.user_id = auth.uid()),
    case when s.user_id = auth.uid() then (select count(*)::int from public.story_views v where v.story_id = s.id) end,
    case when s.user_id = auth.uid() then (select count(*)::int from public.story_replies r where r.story_id = s.id) end,
    exists (select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid())
  from public.stories s
  where s.user_id = p_user_id and s.removed_at is null and s.expires_at > now() and public.can_see_story(s)
  order by s.created_at;
$$;

-- For the poster: who viewed a story, liked it and replied.
create or replace function public.story_activity(p_story_id uuid)
returns table (person_id uuid, name text, avatar_url text, viewed_at timestamptz, liked boolean, reply text, replied_at timestamptz)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.stories s where s.id = p_story_id and (s.user_id = auth.uid() or public.is_admin())) then
    raise exception 'not_found';
  end if;
  return query
    with people as (
      select v.viewer_id as pid from public.story_views v where v.story_id = p_story_id
      union select l.user_id from public.story_likes l where l.story_id = p_story_id
      union select r.sender_id from public.story_replies r where r.story_id = p_story_id
    )
    select pe.pid,
      coalesce((select s.name from public.studios s where s.owner_id = pe.pid limit 1), (select a.artist_name from public.artist_profiles a where a.id = pe.pid), 'EasySesh user'),
      coalesce((select s.photo_urls[1] from public.studios s where s.owner_id = pe.pid limit 1), (select a.avatar_url from public.artist_profiles a where a.id = pe.pid)),
      (select v.viewed_at from public.story_views v where v.story_id = p_story_id and v.viewer_id = pe.pid),
      exists (select 1 from public.story_likes l where l.story_id = p_story_id and l.user_id = pe.pid),
      r.body, r.created_at
    from people pe
    left join lateral (select r.body, r.created_at from public.story_replies r where r.story_id = p_story_id and r.sender_id = pe.pid order by r.created_at desc limit 1) r on true
    order by r.created_at desc nulls last, 4 desc nulls last;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array['post_story(text, text)', 'remove_story(uuid)', 'mark_story_viewed(uuid)', 'like_story(uuid, boolean)',
                           'reply_to_story(uuid, text)', 'story_feed()', 'user_stories(uuid)', 'story_activity(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke execute on function public.can_see_story(public.stories) from anon;

-- Content flags for captions and replies.
create or replace function public.flag_content()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_new jsonb := to_jsonb(new);
  v_fields text[];
  v_field text;
  v_text text;
  v_target public.report_target;
  v_target_id uuid;
  v_author uuid;
  v_hit record;
begin
  case tg_table_name
    when 'messages' then v_fields := array['body']; v_target := 'message'; v_target_id := new.id; v_author := (v_new ->> 'sender_id')::uuid;
    when 'artist_profiles' then v_fields := array['artist_name', 'bio']; v_target := 'user'; v_target_id := new.id; v_author := new.id;
    when 'studios' then v_fields := array['name', 'tagline', 'description', 'rules']; v_target := 'studio'; v_target_id := new.id; v_author := (v_new ->> 'owner_id')::uuid;
    when 'reviews' then v_fields := array['text', 'studio_reply']; v_target := 'review'; v_target_id := new.id; v_author := null;
    when 'artist_reviews' then v_fields := array['text']; v_target := 'user'; v_target_id := (v_new ->> 'artist_id')::uuid; v_author := null;
    when 'stories' then v_fields := array['caption'];
      v_target := case when v_new ->> 'studio_id' is not null then 'studio'::public.report_target else 'user'::public.report_target end;
      v_target_id := coalesce((v_new ->> 'studio_id')::uuid, (v_new ->> 'user_id')::uuid); v_author := (v_new ->> 'user_id')::uuid;
    when 'story_replies' then v_fields := array['body']; v_target := 'user'; v_target_id := (v_new ->> 'sender_id')::uuid; v_author := (v_new ->> 'sender_id')::uuid;
    else return null;
  end case;
  -- System messages and the team's own edits aren't checked.
  if tg_table_name = 'messages' and (v_author is null or coalesce(v_new ->> 'kind', 'text') <> 'text') then return null; end if;
  if v_author is not null and exists (select 1 from public.profiles p where p.id = v_author and p.role = 'admin') then return null; end if;

  foreach v_field in array v_fields loop
    continue when not (v_new ? v_field);
    v_text := v_new ->> v_field;
    continue when coalesce(v_text, '') = '' or (v_old is not null and v_old ->> v_field is not distinct from v_text);
    for v_hit in select * from public.scan_content(v_text, tg_table_name in ('messages', 'story_replies')) loop
      -- One open automatic report per thing and category is enough.
      continue when exists (
        select 1 from public.reports r
        where r.reporter_id is null and r.status = 'open' and r.target_type = v_target and r.target_id = v_target_id
          and r.details like 'Automatic flag: ' || v_hit.category || '%');
      insert into public.reports (reporter_id, target_type, target_id, reason, details)
      values (null, v_target, v_target_id,
              case when v_hit.category = 'off_platform_payment' then 'fraud'::public.report_reason else 'inappropriate'::public.report_reason end,
              'Automatic flag: ' || v_hit.category || ' – matched "' || coalesce(v_hit.matched, '?') || '" in ' || replace(tg_table_name, '_', ' ') || ' ' || replace(v_field, '_', ' ')
                || E'.\n\n"' || left(v_text, 500) || '"');
    end loop;
  end loop;
  return null;
end;
$$;
revoke execute on function public.flag_content() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['stories', 'story_replies'] loop
    if not exists (select 1 from pg_trigger where tgname = 'zz_flag_content' and tgrelid = ('public.' || t)::regclass) then
      execute format('create trigger zz_flag_content after insert or update on public.%I for each row execute function public.flag_content()', t);
    end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_guard' and tgrelid = 'public.stories'::regclass) then
    create trigger zz_staff_write_guard before insert or update or delete on public.stories for each row execute function public.staff_write_guard();
    create trigger zz_staff_write_audit after insert or update or delete on public.stories for each row execute function public.staff_write_audit();
  end if;
end $$;

-- Admin panel: recent stories with the poster, for moderation.
create or replace view public.admin_stories with (security_invoker = true) as
select s.*, coalesce(st.name, a.artist_name) as poster_name, p.email as poster_email,
  (select count(*) from public.story_likes l where l.story_id = s.id) as like_count,
  (select count(*) from public.story_views v where v.story_id = s.id) as view_count,
  (select count(*) from public.story_replies r where r.story_id = s.id) as reply_count
from public.stories s
join public.profiles p on p.id = s.user_id
left join public.studios st on st.id = s.studio_id
left join public.artist_profiles a on a.id = s.user_id;
