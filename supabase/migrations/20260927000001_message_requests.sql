-- EasySesh: studios can start conversations with artists. A conversation a studio starts with an
-- artist it has no history with lands in the artist's "Requests" until the artist accepts it
-- (or replies). A declined request stays closed: the studio can't keep writing.

alter table public.conversations
  add column if not exists request_status text not null default 'accepted'
    check (request_status in ('accepted', 'pending', 'declined')),
  add column if not exists started_by_studio boolean not null default false,
  add column if not exists artist_avatar_url text;

-- Studios can't write in a conversation the artist declined.
drop policy if exists "messages: participants send" on public.messages;
create policy "messages: participants send" on public.messages for insert
  with check (
    sender_id = auth.uid() and kind = 'text' and public.is_active_user()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.artist_id = auth.uid()
             or (public.owns_approved_studio(c.studio_id) and c.request_status <> 'declined'))
    )
  );

-- Artists a studio can message: search by name for studio owners with an approved studio.
create or replace function public.search_artists(p_query text)
returns table (id uuid, artist_name text, city text, genres text[], avatar_url text, is_verified boolean, has_booked boolean)
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
      exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio) as has_booked
    from public.artist_profiles a
    join public.profiles p on p.id = a.id
    where p.status = 'active' and p.role = 'artist' and a.artist_name <> ''
      and (char_length(q) < 2 and exists (select 1 from public.bookings b where b.artist_id = a.id and b.studio_id = my_studio)
           or char_length(q) >= 2 and (a.artist_name ilike '%' || q || '%' or a.city ilike q || '%'))
    order by 7 desc, 6 desc, 2
    limit 30;
end;
$$;

-- Studio → artist: opens (or reuses) the general conversation and sends the first message.
create or replace function public.studio_start_conversation(p_artist_id uuid, p_body text)
returns public.conversations
language plpgsql security definer set search_path = public
as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_studio uuid := (select s.id from public.studios s where s.owner_id = auth.uid() limit 1);
  v_convo uuid;
  v_known boolean;
begin
  if v_studio is null or not public.owns_approved_studio(v_studio) or not public.is_active_user() then
    raise exception 'Only approved studios can message artists.' using errcode = '42501';
  end if;
  if v_body = '' then raise exception 'Write a message first.'; end if;
  if char_length(v_body) > 2000 then raise exception 'Messages can be at most 2000 characters.'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_artist_id and p.role = 'artist' and p.status = 'active') then
    raise exception 'not_found';
  end if;

  v_convo := (select c.id from public.conversations c
              where c.artist_id = p_artist_id and c.studio_id = v_studio and c.booking_id is null);
  if v_convo is null then
    -- Spam protection for cold messages.
    if (select count(*) from public.conversations c
        where c.studio_id = v_studio and c.started_by_studio and c.created_at > now() - interval '1 day') >= 20 then
      raise exception 'You can start 20 new conversations per day. Try again tomorrow.';
    end if;
    -- Artists who already booked or wrote to the studio skip the request step.
    v_known := exists (select 1 from public.bookings b where b.artist_id = p_artist_id and b.studio_id = v_studio)
            or exists (select 1 from public.conversations c where c.artist_id = p_artist_id and c.studio_id = v_studio and not c.started_by_studio);
    v_convo := gen_random_uuid();
    insert into public.conversations (id, artist_id, studio_id, artist_name, studio_name, studio_photo_url, artist_avatar_url, request_status, started_by_studio)
    select v_convo, p_artist_id, s.id,
      coalesce(nullif(a.artist_name, ''), 'Artist'), s.name, s.photo_urls[1], a.avatar_url,
      case when v_known then 'accepted' else 'pending' end, true
    from public.studios s left join public.artist_profiles a on a.id = p_artist_id
    where s.id = v_studio;
  elsif (select c.request_status from public.conversations c where c.id = v_convo) = 'declined' then
    raise exception 'This artist isn''t accepting messages from your studio.';
  end if;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (v_convo, auth.uid(), 'text', v_body);
  return (select c from public.conversations c where c.id = v_convo);
end;
$$;

-- Artist accepts or declines a message request.
create or replace function public.respond_message_request(p_conversation_id uuid, p_accept boolean)
returns public.conversations
language plpgsql security definer set search_path = public
as $$
begin
  update public.conversations c
  set request_status = case when p_accept then 'accepted' else 'declined' end,
      artist_unread = case when p_accept then c.artist_unread else 0 end
  where c.id = p_conversation_id and c.artist_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
  return (select c from public.conversations c where c.id = p_conversation_id);
end;
$$;

-- Messages: replying accepts a request; requests are announced as such.
create or replace function public.on_message_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  c public.conversations;
  owner uuid;
  from_artist boolean;
begin
  c := (select x from public.conversations x where x.id = new.conversation_id);
  owner := (select s.owner_id from public.studios s where s.id = c.studio_id);
  from_artist := new.sender_id = c.artist_id;

  update public.conversations set
    last_message_preview = left(new.body, 140),
    last_message_at = new.created_at,
    artist_unread = artist_unread + case when new.sender_id is null or not from_artist then 1 else 0 end,
    studio_unread = studio_unread + case when new.sender_id is null or from_artist then 1 else 0 end,
    request_status = case when from_artist then 'accepted' else request_status end
  where id = c.id;

  if new.kind = 'text' and not (not from_artist and c.request_status = 'declined') then
    perform public.notify(
      case when from_artist then owner else c.artist_id end,
      'new_message',
      case
        when from_artist then c.artist_name
        when c.request_status = 'pending' then 'Message request · ' || c.studio_name
        else c.studio_name
      end,
      left(new.body, 140),
      c.booking_id, c.id
    );
  end if;
  return new;
end;
$$;
