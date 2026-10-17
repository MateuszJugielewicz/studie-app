-- EasySesh: users can block each other (App Store guideline 1.2). A block works both ways for
-- chat: neither side can send messages in their conversations, and a blocked studio can't start
-- new ones. Admins can see blocks when they look into reports.

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
drop policy if exists "user_blocks: own" on public.user_blocks;
create policy "user_blocks: own" on public.user_blocks for select to authenticated
  using (blocker_id = auth.uid() or public.is_admin());
-- No insert/update/delete policies: users go through the functions below.

create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b) or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

-- The other person in a conversation, seen from the caller.
create or replace function public.conversation_partner(p_conversation_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select case when c.artist_id = auth.uid() then s.owner_id else c.artist_id end
  from public.conversations c join public.studios s on s.id = c.studio_id
  where c.id = p_conversation_id and (c.artist_id = auth.uid() or s.owner_id = auth.uid());
$$;

-- 'none', 'by_me' (I blocked them) or 'by_them'.
create or replace function public.conversation_block_state(p_conversation_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_partner uuid := public.conversation_partner(p_conversation_id);
begin
  if v_partner is null then return 'none'; end if;
  if exists (select 1 from public.user_blocks where blocker_id = auth.uid() and blocked_id = v_partner) then return 'by_me'; end if;
  if exists (select 1 from public.user_blocks where blocker_id = v_partner and blocked_id = auth.uid()) then return 'by_them'; end if;
  return 'none';
end;
$$;

create or replace function public.block_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_user_id is null or p_user_id = auth.uid() then raise exception 'You can''t block yourself.'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then raise exception 'not_found'; end if;
  insert into public.user_blocks (blocker_id, blocked_id) values (auth.uid(), p_user_id)
  on conflict do nothing;
end;
$$;

create or replace function public.unblock_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.user_blocks where blocker_id = auth.uid() and blocked_id = p_user_id;
end;
$$;

-- Blocking from a studio page blocks the studio's owner.
create or replace function public.block_studio(p_studio_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.block_user((select owner_id from public.studios where id = p_studio_id));
end;
$$;

create or replace function public.set_conversation_block(p_conversation_id uuid, p_blocked boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_partner uuid := public.conversation_partner(p_conversation_id);
begin
  if v_partner is null then raise exception 'not_found'; end if;
  if p_blocked then perform public.block_user(v_partner); else perform public.unblock_user(v_partner); end if;
  return public.conversation_block_state(p_conversation_id);
end;
$$;

-- People I've blocked, with a name to show: the artist name, or the studio name for studio owners.
create or replace function public.my_blocked_users()
returns table (user_id uuid, display_name text, avatar_url text, blocked_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.blocked_id,
         coalesce(nullif(a.artist_name, ''), s.name, 'EasySesh user'),
         coalesce(a.avatar_url, s.photo_urls[1]),
         b.created_at
  from public.user_blocks b
  left join public.artist_profiles a on a.id = b.blocked_id
  left join lateral (select x.name, x.photo_urls from public.studios x where x.owner_id = b.blocked_id limit 1) s on true
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

-- No messages between people who blocked each other (covers direct inserts and every function).
create or replace function public.messages_block_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_artist uuid := (select c.artist_id from public.conversations c where c.id = new.conversation_id);
  v_owner uuid := (select s.owner_id from public.conversations c join public.studios s on s.id = c.studio_id
                   where c.id = new.conversation_id);
begin
  if new.sender_id is null then return new; end if;
  if public.is_blocked_between(v_artist, v_owner) then
    raise exception 'You can''t send messages in this conversation.';
  end if;
  return new;
end;
$$;
drop trigger if exists messages_block_guard on public.messages;
create trigger messages_block_guard before insert on public.messages
  for each row execute function public.messages_block_guard();

grant execute on function public.conversation_block_state(uuid), public.block_user(uuid), public.unblock_user(uuid),
  public.block_studio(uuid), public.set_conversation_block(uuid, boolean), public.my_blocked_users() to authenticated;
