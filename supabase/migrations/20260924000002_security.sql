-- EasySesh: identity helpers, sign-up hook, column guards and row-level security.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'active'
  )
  -- Admins must have signed in with a second factor (TOTP).
  and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
$$;

-- Studio features (calendar blocks, replies, studio-side chat, payouts) require an approved studio.
-- Signing up as a studio – or being an artist – never grants them on its own.
create or replace function public.owns_approved_studio(p_studio_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.studios s join public.profiles p on p.id = s.owner_id
    where s.id = p_studio_id and s.owner_id = auth.uid() and s.status = 'approved'
      and p.role = 'studio_owner' and p.status = 'active'
  );
$$;

-- True for the service role, SECURITY DEFINER functions (run as the table owner) and admins.
-- Deliberately SECURITY INVOKER so current_user reflects the real caller.
create or replace function public.is_trusted()
returns boolean
language sql stable
as $$
  select current_user not in ('authenticated', 'anon') or public.is_admin();
$$;

create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

create or replace function public.owns_studio(p_studio_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.studios where id = p_studio_id and owner_id = auth.uid());
$$;

create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    join public.studios s on s.id = c.studio_id
    where c.id = p_conversation_id and (c.artist_id = auth.uid() or s.owner_id = auth.uid())
  );
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sign-up: create the profile row (role comes from sign-up metadata; admins are never self-assigned)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  requested text := coalesce(new.raw_user_meta_data ->> 'role', 'artist');
  assigned public.user_role := case when requested = 'studio_owner' then 'studio_owner'::public.user_role else 'artist'::public.user_role end;
begin
  insert into public.profiles (id, email, role, accepted_terms_version, accepted_terms_at)
  values (
    new.id, coalesce(new.email, ''), assigned,
    new.raw_user_meta_data ->> 'terms_version',
    case when new.raw_user_meta_data ? 'terms_version' then now() end
  );
  if assigned = 'artist' then
    insert into public.artist_profiles (id, artist_name)
    values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''));
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Apple/Google sign-up can't pass metadata; a brand-new account may switch to studio owner once.
create or replace function public.claim_role(p_role public.user_role)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'not_found'; end if;
  if p_role = 'admin' then raise exception 'forbidden'; end if;
  if me.role = p_role then return; end if;
  if me.created_at < now() - interval '1 hour'
     or exists (select 1 from public.bookings where artist_id = me.id)
     or exists (select 1 from public.conversations where artist_id = me.id)
     or exists (select 1 from public.studios where owner_id = me.id) then
    raise exception 'This account already has a role. Contact support to change it.';
  end if;
  update public.profiles set role = p_role where id = me.id;
  if p_role = 'studio_owner' then
    delete from public.artist_profiles where id = me.id;
  else
    insert into public.artist_profiles (id) values (me.id) on conflict do nothing;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Column guards: users may edit their content, never moderation/financial fields.
-- ---------------------------------------------------------------------------
create or replace function public.guard_profiles()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    new.id := old.id;
    new.email := old.email;
    new.role := old.role;
    new.status := old.status;
    new.status_reason := old.status_reason;
    new.is_verified := old.is_verified;
    new.stripe_customer_id := old.stripe_customer_id;
    new.accepted_terms_version := old.accepted_terms_version;
    new.accepted_terms_at := old.accepted_terms_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
create trigger guard_profiles before update on public.profiles
  for each row execute function public.guard_profiles();

create or replace function public.guard_artist_profiles()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.is_verified := false;
    else
      new.is_verified := old.is_verified;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger guard_artist_profiles before insert or update on public.artist_profiles
  for each row execute function public.guard_artist_profiles();

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
    -- Going live/paused only happens through set_studio_active (or an admin), never through a
    -- listing save, so a stale copy in the app can't hide an approved studio.
    new.is_active := old.is_active;
    if new.status <> 'approved' then
      new.is_active := false;
    end if;
  end if;
  return new;
end;
$$;
create trigger guard_studios before insert or update on public.studios
  for each row execute function public.guard_studios();

create or replace function public.guard_notifications()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    -- Only the read flag may change.
    new := old;
    new.is_read := true;
  end if;
  return new;
end;
$$;
create trigger guard_notifications before update on public.notifications
  for each row execute function public.guard_notifications();

create trigger bookings_touch before update on public.bookings
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.artist_profiles enable row level security;
alter table public.device_tokens enable row level security;
alter table public.studios enable row level security;
alter table public.studio_status_events enable row level security;
alter table public.studio_payout_accounts enable row level security;
alter table public.blocked_slots enable row level security;
alter table public.bookings enable row level security;
alter table public.transactions enable row level security;
alter table public.payouts enable row level security;
alter table public.disputes enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.platform_settings enable row level security;

-- profiles
create policy "profiles: read own" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "profiles: update own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- artist_profiles are public to signed-in users (studios see who books them)
create policy "artist_profiles: read" on public.artist_profiles for select to authenticated using (true);
create policy "artist_profiles: insert own" on public.artist_profiles for insert with check (id = auth.uid());
create policy "artist_profiles: update own" on public.artist_profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- device tokens
create policy "device_tokens: own" on public.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- studios: approved+active are public; owners see their own; admins see all
create policy "studios: read public" on public.studios for select
  using ((status = 'approved' and is_active) or owner_id = auth.uid() or public.is_admin()
         or exists (select 1 from public.bookings b where b.studio_id = studios.id and b.artist_id = auth.uid()));
create policy "studios: owner insert" on public.studios for insert with check (owner_id = auth.uid());
create policy "studios: owner update" on public.studios for update using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());

create policy "studio_status_events: read" on public.studio_status_events for select
  using (public.owns_studio(studio_id) or public.is_admin());

create policy "payout_accounts: owner read" on public.studio_payout_accounts for select
  using (public.owns_studio(studio_id) or public.is_admin());

create policy "blocked_slots: owner read" on public.blocked_slots for select
  using (public.owns_studio(studio_id));
create policy "blocked_slots: approved owner write" on public.blocked_slots for insert
  with check (public.owns_approved_studio(studio_id));
create policy "blocked_slots: approved owner delete" on public.blocked_slots for delete
  using (public.owns_approved_studio(studio_id));

-- bookings & money: read-only for participants; all writes go through edge functions / RPCs
create policy "bookings: participants read" on public.bookings for select
  using (artist_id = auth.uid() or public.owns_studio(studio_id) or public.is_admin());
create policy "transactions: participants read" on public.transactions for select
  using (artist_id = auth.uid() or public.owns_studio(studio_id) or public.is_admin());
create policy "payouts: owner read" on public.payouts for select
  using (public.owns_studio(studio_id) or public.is_admin());
create policy "disputes: participants read" on public.disputes for select
  using (opened_by = auth.uid() or public.is_admin()
         or exists (select 1 from public.bookings b where b.id = booking_id and (b.artist_id = auth.uid() or public.owns_studio(b.studio_id))));

-- chat
create policy "conversations: participants read" on public.conversations for select
  using (artist_id = auth.uid() or public.owns_studio(studio_id) or public.is_admin());
create policy "messages: participants read" on public.messages for select
  using (public.is_conversation_participant(conversation_id) or public.is_admin());
-- Artists can write in their own threads; the studio side only once the studio is approved.
create policy "messages: participants send" on public.messages for insert
  with check (
    sender_id = auth.uid() and kind = 'text' and public.is_active_user()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.artist_id = auth.uid() or public.owns_approved_studio(c.studio_id))
    )
  );

-- notifications
create policy "notifications: own read" on public.notifications for select using (user_id = auth.uid());
create policy "notifications: own mark read" on public.notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- reviews: public; artists write one per completed booking; replies via RPC
create policy "reviews: read" on public.reviews for select using (not is_hidden or artist_id = auth.uid() or public.owns_studio(studio_id) or public.is_admin());
create policy "reviews: artist insert" on public.reviews for insert with check (
  artist_id = auth.uid()
  and exists (
    select 1 from public.bookings b
    where b.id = booking_id and b.artist_id = auth.uid() and b.studio_id = reviews.studio_id
      and b.status = 'completed' and not b.has_review
  )
);

-- reports
create policy "reports: insert own" on public.reports for insert with check (reporter_id = auth.uid());
create policy "reports: read own or admin" on public.reports for select using (reporter_id = auth.uid() or public.is_admin());

create policy "platform_settings: read" on public.platform_settings for select using (true);

-- ---------------------------------------------------------------------------
-- Storage: public "media" bucket; users write only under their own user-id prefix.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('media', 'media', true) on conflict (id) do nothing;

create policy "media: upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "media: update own folder" on storage.objects for update to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "media: delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
