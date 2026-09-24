-- =====================================================================
-- SONORA update 2026-09-26 (for a database that already ran setup.sql)
--  1. Fix: "You already have a studio" when saving a studio application again
--  2. New: Contact support (tickets in the app, replies from the admin dashboard)
--
-- Supabase → SQL Editor → New query → paste this whole file → Run.
-- Safe to run more than once; it keeps existing data.
-- =====================================================================

-- 1. Studio save fix -----------------------------------------------------
create or replace function public.guard_studios()
returns trigger language plpgsql as $$
begin
  -- Keep the "from" price in sync with the session types.
  new.price_from := coalesce((select min((t.value ->> 'hourly_rate')::int) from jsonb_array_elements(new.session_types) as t), 0);

  if public.is_trusted() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Upsert of an existing row: Postgres runs this INSERT trigger before resolving the conflict.
    -- The UPDATE branch below guards the row that actually gets written, so leave it alone here.
    if exists (select 1 from public.studios where id = new.id) then
      return new;
    end if;
    if new.owner_id is distinct from auth.uid()
       or not exists (select 1 from public.profiles where id = auth.uid() and role = 'studio_owner' and status = 'active') then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    if exists (select 1 from public.studios where owner_id = auth.uid() and id <> new.id) then
      raise exception 'You already have a studio.';
    end if;
    new.status := 'draft';
    new.is_active := false;
    new.is_verified := false;
    new.admin_note := null;
    new.rating_average := 0;
    new.review_count := 0;
    new.booking_count := 0;
    new.submitted_at := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.created_at := now();
  else
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.is_verified := old.is_verified;
    new.admin_note := old.admin_note;
    new.rating_average := old.rating_average;
    new.review_count := old.review_count;
    new.booking_count := old.booking_count;
    new.submitted_at := old.submitted_at;
    new.reviewed_at := old.reviewed_at;
    new.reviewed_by := old.reviewed_by;
    new.created_at := old.created_at;
    if new.status <> 'approved' then
      new.is_active := false;
    end if;
  end if;
  return new;
end;
$$;

-- 2. Support -------------------------------------------------------------
-- Sonora: in-app support. Users open tickets from the app, admins answer them in the admin dashboard.
-- Tables are read-only for clients; every write goes through the RPCs below.

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  subject text not null check (char_length(subject) between 3 and 120),
  category text not null default 'other'
    check (category in ('account', 'booking', 'payment', 'studio', 'bug', 'other')),
  booking_id uuid references public.bookings (id) on delete set null,
  -- open: waiting for Sonora · answered: waiting for the user · closed: done
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  user_unread integer not null default 0,
  admin_unread integer not null default 0,
  last_message_preview text not null default '',
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id, last_message_at desc);
create index if not exists support_tickets_status_idx on public.support_tickets (status, last_message_at desc);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  from_admin boolean not null default false,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists support_messages_ticket_idx on public.support_messages (ticket_id, created_at);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
drop policy if exists "support_tickets: own or admin read" on public.support_tickets;
create policy "support_tickets: own or admin read" on public.support_tickets for select
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "support_messages: own or admin read" on public.support_messages;
create policy "support_messages: own or admin read" on public.support_messages for select
  using (public.is_admin() or exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid()));

-- Admin inbox rows with who wrote in.
drop view if exists public.admin_support_tickets;
create view public.admin_support_tickets with (security_invoker = true) as
select t.*, p.email as user_email, p.role as user_role,
  coalesce(nullif(a.artist_name, ''), nullif(s.name, ''), p.email) as user_name,
  b.reference as booking_reference
from public.support_tickets t
join public.profiles p on p.id = t.user_id
left join public.artist_profiles a on a.id = t.user_id
left join public.studios s on s.owner_id = t.user_id
left join public.bookings b on b.id = t.booking_id;

-- Adds a message to a ticket and updates its status, counters and preview.
create or replace function public.add_support_message(p_ticket_id uuid, p_body text, p_from_admin boolean)
returns public.support_messages
language plpgsql security definer set search_path = public
as $$
declare
  t public.support_tickets;
  m public.support_messages;
  body text := btrim(coalesce(p_body, ''));
begin
  select * into t from public.support_tickets where id = p_ticket_id for update;
  if t.id is null then raise exception 'not_found'; end if;
  if body = '' then raise exception 'Write a message first.'; end if;
  if char_length(body) > 4000 then raise exception 'Message is too long (max 4000 characters).'; end if;

  insert into public.support_messages (ticket_id, sender_id, from_admin, body)
  values (t.id, auth.uid(), p_from_admin, body)
  returning * into m;

  update public.support_tickets set
    status = case when p_from_admin then 'answered' else 'open' end,
    user_unread = case when p_from_admin then user_unread + 1 else 0 end,
    admin_unread = case when p_from_admin then 0 else admin_unread + 1 end,
    last_message_preview = left(body, 140),
    last_message_at = m.created_at,
    closed_at = null
  where id = t.id;

  if p_from_admin then
    perform public.notify(t.user_id, 'system', 'Sonora support replied', t.subject || ': ' || left(body, 120));
  end if;
  return m;
end;
$$;
revoke execute on function public.add_support_message from public, anon, authenticated;

-- App: open a new ticket with its first message.
create or replace function public.create_support_ticket(p_subject text, p_category text, p_body text, p_booking_id uuid default null)
returns public.support_tickets
language plpgsql security definer set search_path = public
as $$
declare
  t public.support_tickets;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_booking_id is not null and not exists (
    select 1 from public.bookings b
    where b.id = p_booking_id and (b.artist_id = auth.uid() or public.owns_studio(b.studio_id))
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- Light spam protection.
  if (select count(*) from public.support_tickets where user_id = auth.uid() and status <> 'closed') >= 5 then
    raise exception 'You already have 5 open requests. Please continue in one of them.';
  end if;
  if (select count(*) from public.support_tickets where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Too many requests. Please try again later.';
  end if;

  insert into public.support_tickets (user_id, subject, category, booking_id)
  values (auth.uid(), btrim(coalesce(p_subject, '')), coalesce(nullif(p_category, ''), 'other'), p_booking_id)
  returning * into t;
  perform public.add_support_message(t.id, p_body, false);
  select * into t from public.support_tickets where id = t.id;
  return t;
end;
$$;

-- App (ticket owner) or admin dashboard: reply in a ticket.
create or replace function public.send_support_message(p_ticket_id uuid, p_body text)
returns public.support_messages
language plpgsql security definer set search_path = public
as $$
declare
  owner uuid;
begin
  select user_id into owner from public.support_tickets where id = p_ticket_id;
  if owner is null then raise exception 'not_found'; end if;
  if public.is_admin() then
    return public.add_support_message(p_ticket_id, p_body, true);
  elsif owner = auth.uid() then
    return public.add_support_message(p_ticket_id, p_body, false);
  end if;
  raise exception 'forbidden' using errcode = '42501';
end;
$$;

-- Clears the unread counter for whoever is reading.
create or replace function public.mark_support_ticket_read(p_ticket_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() then
    update public.support_tickets set admin_unread = 0 where id = p_ticket_id;
  else
    update public.support_tickets set user_unread = 0 where id = p_ticket_id and user_id = auth.uid();
  end if;
end;
$$;

-- The user can close their own ticket; admins can close or reopen any ticket.
create or replace function public.set_support_ticket_status(p_ticket_id uuid, p_status text)
returns public.support_tickets
language plpgsql security definer set search_path = public
as $$
declare
  t public.support_tickets;
begin
  if p_status not in ('open', 'answered', 'closed') then raise exception 'invalid status'; end if;
  select * into t from public.support_tickets where id = p_ticket_id for update;
  if t.id is null then raise exception 'not_found'; end if;
  if not public.is_admin() and not (t.user_id = auth.uid() and p_status = 'closed') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.support_tickets
  set status = p_status, closed_at = case when p_status = 'closed' then now() end
  where id = t.id
  returning * into t;
  return t;
end;
$$;

-- Admins see new support messages live.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'support_messages') then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end $$;

grant select, insert, update, delete on public.support_tickets, public.support_messages, public.admin_support_tickets to authenticated, service_role;
grant execute on function public.create_support_ticket, public.send_support_message, public.mark_support_ticket_read,
  public.set_support_ticket_status to authenticated, service_role;
revoke execute on function public.add_support_message from anon, authenticated;
