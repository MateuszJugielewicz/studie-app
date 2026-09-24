-- EasySesh: in-app support. Users open tickets from the app, admins answer them in the admin dashboard.
-- Tables are read-only for clients; every write goes through the RPCs below.

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  subject text not null check (char_length(subject) between 3 and 120),
  category text not null default 'other'
    check (category in ('account', 'booking', 'payment', 'studio', 'bug', 'other')),
  booking_id uuid references public.bookings (id) on delete set null,
  -- open: waiting for EasySesh · answered: waiting for the user · closed: done
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  user_unread integer not null default 0,
  admin_unread integer not null default 0,
  last_message_preview text not null default '',
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index support_tickets_user_idx on public.support_tickets (user_id, last_message_at desc);
create index support_tickets_status_idx on public.support_tickets (status, last_message_at desc);

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  from_admin boolean not null default false,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index support_messages_ticket_idx on public.support_messages (ticket_id, created_at);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
create policy "support_tickets: own or admin read" on public.support_tickets for select
  using (user_id = auth.uid() or public.is_admin());
create policy "support_messages: own or admin read" on public.support_messages for select
  using (public.is_admin() or exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid()));

-- Admin inbox rows with who wrote in.
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
  new_id uuid := gen_random_uuid();
  body text := btrim(coalesce(p_body, ''));
begin
  -- Plain assignments on purpose: the Supabase SQL Editor treats "select ... in-to var"
  -- as a new table and breaks the function when this file is pasted.
  perform 1 from public.support_tickets where id = p_ticket_id for update;
  t := (select x from public.support_tickets x where x.id = p_ticket_id);
  if t.id is null then raise exception 'not_found'; end if;
  if body = '' then raise exception 'Write a message first.'; end if;
  if char_length(body) > 4000 then raise exception 'Message is too long (max 4000 characters).'; end if;

  insert into public.support_messages (id, ticket_id, sender_id, from_admin, body)
  values (new_id, t.id, auth.uid(), p_from_admin, body);
  m := (select x from public.support_messages x where x.id = new_id);

  update public.support_tickets set
    status = case when p_from_admin then 'answered' else 'open' end,
    user_unread = case when p_from_admin then user_unread + 1 else 0 end,
    admin_unread = case when p_from_admin then 0 else admin_unread + 1 end,
    last_message_preview = left(body, 140),
    last_message_at = m.created_at,
    closed_at = null
  where id = t.id;

  if p_from_admin then
    perform public.notify(t.user_id, 'system', 'EasySesh support replied', t.subject || ': ' || left(body, 120));
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
  new_id uuid := gen_random_uuid();
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

  insert into public.support_tickets (id, user_id, subject, category, booking_id)
  values (new_id, auth.uid(), btrim(coalesce(p_subject, '')), coalesce(nullif(p_category, ''), 'other'), p_booking_id);
  perform public.add_support_message(new_id, p_body, false);
  return (select x from public.support_tickets x where x.id = new_id);
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
  owner := (select user_id from public.support_tickets where id = p_ticket_id);
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
  perform 1 from public.support_tickets where id = p_ticket_id for update;
  t := (select x from public.support_tickets x where x.id = p_ticket_id);
  if t.id is null then raise exception 'not_found'; end if;
  if not public.is_admin() and not (t.user_id = auth.uid() and p_status = 'closed') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.support_tickets
  set status = p_status, closed_at = case when p_status = 'closed' then now() end
  where id = t.id;
  return (select x from public.support_tickets x where x.id = t.id);
end;
$$;

-- Admins see new support messages live.
alter publication supabase_realtime add table public.support_messages;
