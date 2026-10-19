-- Admin team tools:
--   1. Ranks: owner > admin > support. Only owners change ranks and read the audit log; support staff
--      can read everything but only answer support tickets.
--   2. Audit log of every change a staff member makes (automatic, via triggers).
--   3. Account change notices: when staff change someone's account, the user gets an email from
--      noreply@ saying what changed and why (the admin panel asks for the explanation and sends it in
--      the X-Admin-Reason header). Replies go to support@.
--   4. "View as user": read-only sessions made by the admin-view-as function. Every write from such a
--      session is refused (PostgREST pre-request check, storage policies, edge functions).
--   5. Emails sent from the admin panel (admin-send-email) are kept for reference.
--   6. Site banners (outages, announcements) shown on the website and in the apps.

-- ---------------------------------------------------------------------------
-- 1. Ranks
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists admin_rank text check (admin_rank in ('owner', 'admin', 'support'));
update public.profiles set admin_rank = 'owner' where role = 'admin' and admin_rank is null;

-- The caller's rank, or null when they aren't signed-in staff (with two-factor). Admins without a
-- rank (made before ranks existed) count as 'admin'.
create or replace function public.admin_rank()
returns text
language sql stable security definer set search_path = public
as $$
  select case when public.is_admin() then (select coalesce(p.admin_rank, 'admin') from public.profiles p where p.id = auth.uid()) end;
$$;

create or replace function public.has_admin_rank(p_min text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(array_position(array['support', 'admin', 'owner'], public.admin_rank())
                  >= array_position(array['support', 'admin', 'owner'], p_min), false);
$$;

create or replace function public.guard_profiles()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if not public.is_trusted() then
    new.id := old.id;
    new.email := old.email;
    new.role := old.role;
    new.status := old.status;
    new.status_reason := old.status_reason;
    new.is_verified := old.is_verified;
    new.email_verified_at := old.email_verified_at;
    new.admin_rank := old.admin_rank;
    new.stripe_customer_id := old.stripe_customer_id;
    new.accepted_terms_version := old.accepted_terms_version;
    new.accepted_terms_at := old.accepted_terms_at;
    new.created_at := old.created_at;
  end if;
  -- Staff can't hand out or take away admin access unless they're an owner.
  if auth.uid() is not null and public.is_admin()
     and (new.admin_rank is distinct from old.admin_rank
          or (new.role is distinct from old.role and 'admin' in (new.role::text, old.role::text)))
     and not public.has_admin_rank('owner') then
    raise exception 'Only owners can change who is on the admin team.' using errcode = '42501';
  end if;
  if new.role <> 'admin' then new.admin_rank := null; end if;
  if old.admin_rank = 'owner' and new.admin_rank is distinct from 'owner'
     and not exists (select 1 from public.profiles p where p.admin_rank = 'owner' and p.id <> old.id) then
    raise exception 'EasySesh needs at least one owner.';
  end if;
  return new;
end;
$$;

-- Owner adds someone to the team (by email), changes their rank, or removes them (p_rank null).
create or replace function public.admin_set_rank(p_email text, p_rank text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := (select p.id from public.profiles p where lower(p.email) = lower(btrim(p_email)));
begin
  if not public.has_admin_rank('owner') then raise exception 'Only owners can change who is on the admin team.' using errcode = '42501'; end if;
  if v_user is null then raise exception 'No EasySesh account uses this email. Ask them to sign up first.'; end if;
  if p_rank is not null and p_rank not in ('owner', 'admin', 'support') then raise exception 'Unknown rank.'; end if;
  if p_rank is null then
    update public.profiles set role = 'artist', admin_rank = null where id = v_user and role = 'admin';
  else
    if exists (select 1 from public.studios s where s.owner_id = v_user) then
      raise exception 'Studio owners can''t be on the admin team. Use a separate account.';
    end if;
    update public.profiles set role = 'admin', admin_rank = p_rank where id = v_user;
  end if;
end;
$$;
revoke execute on function public.admin_set_rank(text, text) from public, anon;
grant execute on function public.admin_set_rank(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Audit log
-- ---------------------------------------------------------------------------
create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid references public.profiles (id) on delete set null,
  admin_email text,
  admin_rank text,
  action text not null,
  target_table text,
  target_id text,
  affected_user uuid,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created on public.admin_audit_log (created_at desc);
alter table public.admin_audit_log enable row level security;
create policy "admin_audit_log: owners read" on public.admin_audit_log for select using (public.has_admin_rank('owner'));
revoke insert, update, delete on public.admin_audit_log from public, anon, authenticated;

-- The explanation the admin panel sends with each change (base64 of UTF-8 in X-Admin-Reason).
create or replace function public.admin_reason()
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  v_raw text;
begin
  v_raw := nullif(current_setting('request.headers', true), '')::json ->> 'x-admin-reason';
  if v_raw is null or v_raw = '' then return null; end if;
  return left(convert_from(decode(v_raw, 'base64'), 'UTF8'), 2000);
exception when others then
  return null;
end;
$$;

-- Staff log entries for actions that don't change a table (view as, emails, refunds via Stripe).
create or replace function public.write_admin_audit(p_admin uuid, p_action text, p_table text, p_target text, p_user uuid, p_reason text, p_details jsonb)
returns void
language sql security definer set search_path = public
as $$
  insert into public.admin_audit_log (admin_id, admin_email, admin_rank, action, target_table, target_id, affected_user, reason, details)
  select p_admin, p.email, coalesce(p.admin_rank, 'admin'), p_action, p_table, p_target, p_user, p_reason, coalesce(p_details, '{}'::jsonb)
  from public.profiles p where p.id = p_admin;
$$;
revoke execute on function public.write_admin_audit(uuid, text, text, text, uuid, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Account change notices (email from noreply@ to the person whose account was changed)
-- ---------------------------------------------------------------------------
create table if not exists public.account_change_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  txid bigint not null,
  changes jsonb not null default '[]'::jsonb,
  reason text,
  emailed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, txid)
);
alter table public.account_change_notices enable row level security;
create policy "account_change_notices: own or admin read" on public.account_change_notices for select
  using (user_id = auth.uid() or public.is_admin());

create or replace function public.on_account_change_notice()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- pg_net sends after commit, so every change made in this request is in the notice by then.
  perform public.call_edge_function('account-change-email', jsonb_build_object('notice_id', new.id));
  return new;
end;
$$;
create trigger on_account_change_notice after insert on public.account_change_notices
  for each row execute function public.on_account_change_notice();

-- Readable names for the summary ("Studio: status changed from Pending review to Approved").
create or replace function public.humanize(p_text text)
returns text
language sql immutable
as $$
  select initcap(replace(coalesce(p_text, ''), '_', ' '));
$$;

create or replace function public.audit_value(p_value jsonb)
returns text
language sql immutable
as $$
  select case
    when p_value is null or p_value = 'null'::jsonb then '–'
    when jsonb_typeof(p_value) = 'string' and (p_value #>> '{}') ~ '^[a-z]+(_[a-z]+)*$' then lower(public.humanize(p_value #>> '{}'))
    when jsonb_typeof(p_value) = 'string' then left(p_value #>> '{}', 120)
    else left(p_value::text, 120)
  end;
$$;

-- ---------------------------------------------------------------------------
-- The staff triggers: rank check before, audit + notice after.
-- ---------------------------------------------------------------------------
create or replace function public.staff_write_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null and public.admin_rank() = 'support'
     and tg_table_name not in ('support_tickets', 'support_messages')
     and not (tg_table_name = 'profiles' and tg_op = 'UPDATE' and to_jsonb(old) ->> 'id' = auth.uid()::text) then
    raise exception 'Your admin rank (support) can only answer support requests.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.staff_write_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_changes jsonb := '{}'::jsonb;
  v_key text;
  v_user uuid;
  v_studio uuid;
  v_label text;
  v_lines jsonb := '[]'::jsonb;
  v_reason text := public.admin_reason();
  v_ignored text[] := array['updated_at', 'created_at', 'price_from', 'rating_average', 'review_count', 'booking_count', 'search_text', 'last_message_preview'];
begin
  if auth.uid() is null or not public.is_admin() then return null; end if;

  if tg_op = 'UPDATE' then
    for v_key in select jsonb_object_keys(v_new) loop
      continue when v_key = any (v_ignored);
      if v_new -> v_key is distinct from v_old -> v_key then
        v_changes := v_changes || jsonb_build_object(v_key, jsonb_build_object('old', left(coalesce(v_old ->> v_key, ''), 500), 'new', left(coalesce(v_new ->> v_key, ''), 500)));
      end if;
    end loop;
    if v_changes = '{}'::jsonb then return null; end if;
  else
    for v_key in select jsonb_object_keys(v_row) loop
      continue when v_key = any (v_ignored);
      v_changes := v_changes || jsonb_build_object(v_key, left(coalesce(v_row ->> v_key, ''), 500));
    end loop;
  end if;

  -- Whose account is this about?
  v_studio := case when tg_table_name = 'studios' then (v_row ->> 'id')::uuid
                   when v_row ? 'studio_id' and tg_table_name in ('studio_offers', 'promo_codes', 'studio_promotions', 'studio_fee_ledger', 'studio_fee_invoices', 'studio_artist_links')
                   then nullif(v_row ->> 'studio_id', '')::uuid end;
  v_user := case tg_table_name
    when 'profiles' then (v_row ->> 'id')::uuid
    when 'artist_profiles' then (v_row ->> 'id')::uuid
    when 'moderation_actions' then nullif(v_row ->> 'user_id', '')::uuid
    when 'reviews' then nullif(v_row ->> 'artist_id', '')::uuid
    else (select s.owner_id from public.studios s where s.id = v_studio)
  end;

  insert into public.admin_audit_log (admin_id, admin_email, admin_rank, action, target_table, target_id, affected_user, reason, details)
  select auth.uid(), p.email, coalesce(p.admin_rank, 'admin'), lower(tg_op), tg_table_name, v_row ->> 'id', v_user, v_reason, v_changes
  from public.profiles p where p.id = auth.uid();

  -- Tell the person, unless it's the staff member's own account or not an account table.
  if v_user is null or v_user = auth.uid()
     or tg_table_name not in ('profiles', 'artist_profiles', 'studios', 'studio_offers', 'promo_codes', 'studio_promotions',
                              'studio_fee_ledger', 'studio_fee_invoices', 'moderation_actions', 'reviews', 'studio_artist_links') then
    return null;
  end if;
  v_label := case tg_table_name
    when 'profiles' then 'Account' when 'artist_profiles' then 'Artist profile' when 'studios' then 'Studio'
    when 'studio_offers' then 'Studio offer' when 'promo_codes' then 'Promo code' when 'studio_promotions' then 'Promotion'
    when 'studio_fee_ledger' then 'Platform fee balance' when 'studio_fee_invoices' then 'Platform fee invoice'
    when 'moderation_actions' then 'Moderation' when 'reviews' then 'Review' else 'Studio and artist link' end;
  if tg_op = 'UPDATE' then
    select coalesce(jsonb_agg(v_label || ': ' || lower(public.humanize(k)) || ' changed from ' || public.audit_value(v_old -> k) || ' to ' || public.audit_value(v_new -> k)), '[]'::jsonb)
      into v_lines from jsonb_object_keys(v_changes) k
      where k not in ('id', 'owner_id', 'studio_id', 'user_id', 'session_types', 'add_ons', 'opening_hours', 'photo_urls', 'equipment', 'settings');
    -- Big fields: just say they changed.
    select v_lines || coalesce(jsonb_agg(v_label || ': ' || lower(public.humanize(k)) || ' updated'), '[]'::jsonb)
      into v_lines from jsonb_object_keys(v_changes) k
      where k in ('session_types', 'add_ons', 'opening_hours', 'photo_urls', 'equipment', 'settings');
  elsif tg_op = 'INSERT' then
    v_lines := jsonb_build_array(v_label || ': ' || case tg_table_name
      when 'moderation_actions' then public.humanize(v_row ->> 'action') || coalesce(' – ' || nullif(v_row ->> 'reason', ''), '')
      when 'studio_fee_ledger' then public.humanize(v_row ->> 'kind') || ' (' || public.format_money((v_row ->> 'amount')::int, v_row ->> 'currency') || ')'
      when 'promo_codes' then 'code ' || (v_row ->> 'code') || ' added'
      when 'studio_offers' then (v_row ->> 'title') || ' added'
      else 'added' end);
  else
    v_lines := jsonb_build_array(v_label || ': removed' || coalesce(' (' || coalesce(v_row ->> 'title', v_row ->> 'code') || ')', ''));
  end if;
  if jsonb_array_length(v_lines) = 0 then return null; end if;

  insert into public.account_change_notices (user_id, txid, changes, reason)
  values (v_user, txid_current(), v_lines, v_reason)
  on conflict (user_id, txid) do update set
    changes = public.account_change_notices.changes || excluded.changes,
    reason = coalesce(public.account_change_notices.reason, excluded.reason);
  return null;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'artist_profiles', 'studios', 'bookings', 'reviews', 'artist_reviews', 'rating_disputes', 'reports',
                           'disputes', 'support_tickets', 'support_messages', 'moderation_actions', 'app_changelog', 'app_terms',
                           'studio_promotions', 'studio_fee_ledger', 'studio_fee_invoices', 'payouts', 'transactions', 'promo_codes',
                           'studio_offers', 'studio_artist_links', 'platform_settings']
  loop
    if to_regclass('public.' || t) is null then continue; end if;
    if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_guard' and tgrelid = ('public.' || t)::regclass) then
      execute format('create trigger zz_staff_write_guard before insert or update or delete on public.%I for each row execute function public.staff_write_guard()', t);
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_audit' and tgrelid = ('public.' || t)::regclass) then
      execute format('create trigger zz_staff_write_audit after insert or update or delete on public.%I for each row execute function public.staff_write_audit()', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 4. View as user (read-only sessions)
-- ---------------------------------------------------------------------------
create table if not exists public.impersonation_sessions (
  session_id uuid primary key,
  admin_id uuid references public.profiles (id) on delete set null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.impersonation_sessions enable row level security;
create policy "impersonation_sessions: owners read" on public.impersonation_sessions for select using (public.has_admin_rank('owner'));

create or replace function public.is_impersonating()
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_sid text;
begin
  v_sid := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id';
  if v_sid is null or v_sid !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  return exists (select 1 from public.impersonation_sessions s where s.session_id = v_sid::uuid);
exception when others then
  return false;
end;
$$;

-- Runs before every API request (pgrst.db_pre_request): view-as sessions may only read.
create or replace function public.check_view_only_request()
returns void
language plpgsql stable security definer set search_path = public
as $$
declare
  v_method text := coalesce(current_setting('request.method', true), 'GET');
  v_path text := coalesce(current_setting('request.path', true), '');
begin
  if v_method in ('GET', 'HEAD', 'OPTIONS') then return; end if;
  if not public.is_impersonating() then return; end if;
  if v_path ~ '^/rpc/(quote_booking|check_promo_code|studio_busy_intervals|current_terms_version|search_artists|conversation_block_state|my_blocked_users|export_my_data|admin_rank)$' then
    return;
  end if;
  raise exception 'View only: you''re seeing EasySesh as this user, so nothing can be changed.' using errcode = '42501';
end;
$$;
grant execute on function public.check_view_only_request() to anon, authenticated;

-- Storage writes don't go through PostgREST.
do $$
begin
  if to_regclass('storage.objects') is not null then
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'view-as: no uploads') then
      create policy "view-as: no uploads" on storage.objects as restrictive for insert with check (not public.is_impersonating());
      create policy "view-as: no updates" on storage.objects as restrictive for update using (not public.is_impersonating());
      create policy "view-as: no removals" on storage.objects as restrictive for delete using (not public.is_impersonating());
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Emails sent from the admin panel
-- ---------------------------------------------------------------------------
create table if not exists public.admin_emails (
  id uuid primary key default gen_random_uuid(),
  sent_by uuid references public.profiles (id) on delete set null,
  sender_email text,
  from_address text not null,
  to_addresses text[] not null,
  subject text not null,
  body text not null,
  resend_id text,
  created_at timestamptz not null default now()
);
alter table public.admin_emails enable row level security;
create policy "admin_emails: staff read" on public.admin_emails for select using (public.is_admin());

-- ---------------------------------------------------------------------------
-- 6. Site banners
-- ---------------------------------------------------------------------------
create table if not exists public.site_banners (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'info' check (kind in ('info', 'warning', 'outage', 'success')),
  -- everyone | guests | artist | studio_owner
  audience text not null default 'everyone' check (audience in ('everyone', 'guests', 'artist', 'studio_owner')),
  title text not null check (char_length(btrim(title)) between 2 and 120),
  body text not null default '' check (char_length(body) <= 600),
  link_url text check (link_url is null or link_url ~ '^https://'),
  link_label text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  dismissible boolean not null default true,
  is_active boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.site_banners enable row level security;
create policy "site_banners: read live" on public.site_banners for select
  using ((is_active and starts_at <= now() and (ends_at is null or ends_at > now())) or public.is_admin());
create policy "site_banners: admins write" on public.site_banners for insert with check (public.has_admin_rank('admin'));
create policy "site_banners: admins update" on public.site_banners for update using (public.has_admin_rank('admin')) with check (public.has_admin_rank('admin'));
create policy "site_banners: admins remove" on public.site_banners for delete using (public.has_admin_rank('admin'));

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_audit' and tgrelid = 'public.site_banners'::regclass) then
    create trigger zz_staff_write_audit after insert or update or delete on public.site_banners for each row execute function public.staff_write_audit();
  end if;
end $$;
