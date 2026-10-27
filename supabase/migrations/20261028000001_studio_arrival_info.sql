-- Arrival info: practical information a studio wants every artist to get once a booking is confirmed
-- (directions, door or key-box code, parking, what to bring). It's private: artists never see it before
-- they've booked. When a booking becomes confirmed (card bookings only after payment), it's sent
-- automatically as a message from the studio in the booking's conversation, which also notifies the
-- artist. Each booking gets it once. Studios can choose not to send it for pay-at-studio (cash) bookings.

create table if not exists public.studio_arrival_info (
  studio_id uuid primary key references public.studios (id) on delete cascade,
  body text not null default '' check (char_length(body) <= 2000),
  send_for_cash boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.studio_arrival_info enable row level security;
create policy "studio_arrival_info: owner or admin reads" on public.studio_arrival_info for select
  using (public.is_admin() or exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));
create policy "studio_arrival_info: owner adds" on public.studio_arrival_info for insert
  with check (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));
create policy "studio_arrival_info: owner updates" on public.studio_arrival_info for update
  using (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.studios s where s.id = studio_id and s.owner_id = auth.uid()));
revoke all on public.studio_arrival_info from anon;
grant select, insert, update on public.studio_arrival_info to authenticated;

-- Which bookings already got it (so moving or re-confirming a booking doesn't send it twice).
create table if not exists public.booking_arrival_info_sent (
  booking_id uuid primary key references public.bookings (id) on delete cascade,
  sent_at timestamptz not null default now()
);
alter table public.booking_arrival_info_sent enable row level security;
revoke all on public.booking_arrival_info_sent from anon, authenticated;

create or replace function public.send_arrival_info(p_booking_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  b public.bookings;
  s public.studios;
  info public.studio_arrival_info;
  convo uuid;
begin
  b := (select x from public.bookings x where x.id = p_booking_id);
  if b.id is null or b.status <> 'confirmed' then return false; end if;
  s := (select x from public.studios x where x.id = b.studio_id);
  info := (select x from public.studio_arrival_info x where x.studio_id = b.studio_id);
  if info.studio_id is null or btrim(info.body) = '' then return false; end if;
  if b.payment_status = 'pay_at_studio' and not info.send_for_cash then return false; end if;
  if exists (select 1 from public.booking_arrival_info_sent x where x.booking_id = b.id) then return false; end if;

  -- Never let this block confirming the booking itself.
  begin
    convo := (select c.id from public.conversations c where c.booking_id = b.id limit 1);
    if convo is null then
      insert into public.conversations (artist_id, studio_id, booking_id, artist_name, studio_name, studio_photo_url, artist_avatar_url)
      values (b.artist_id, s.id, b.id, coalesce(nullif(b.artist_name, ''), 'Artist'), s.name, s.photo_urls[1],
              (select a.avatar_url from public.artist_profiles a where a.id = b.artist_id))
      returning id into convo;
    end if;
    insert into public.messages (conversation_id, sender_id, kind, body)
    values (convo, s.owner_id, 'text', btrim(info.body));
    insert into public.booking_arrival_info_sent (booking_id) values (b.id);
    return true;
  exception when others then
    raise warning 'arrival info for booking % not sent: %', b.id, sqlerrm;
    return false;
  end;
end;
$$;
revoke execute on function public.send_arrival_info(uuid) from public, anon, authenticated;

-- Send it from the booking trigger when a booking becomes confirmed.
do $$
declare d text;
begin
  select replace(pg_get_functiondef('public.on_booking_change'::regproc), E'\r', '') into d;
  if position('perform public.send_arrival_info(new.id);' in d) > 0 then return; end if;
  if position('update public.studios set booking_count = booking_count + 1 where id = new.studio_id;' in d) = 0 then
    raise exception 'on_booking_change has changed; add send_arrival_info by hand';
  end if;
  execute replace(d, 'update public.studios set booking_count = booking_count + 1 where id = new.studio_id;',
    'update public.studios set booking_count = booking_count + 1 where id = new.studio_id;
        perform public.send_arrival_info(new.id);');
end $$;
