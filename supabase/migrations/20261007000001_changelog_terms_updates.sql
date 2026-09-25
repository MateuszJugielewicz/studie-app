-- EasySesh: admins publish a changelog ("What's new" in the app). An entry can also be marked as a
-- legal update: every user must then read the documents again and accept them before they can
-- keep using the app.

create table if not exists public.app_changelog (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  title text not null,
  body text not null default '',
  -- 'all', 'artist' or 'studio_owner'
  audience text not null default 'all' check (audience in ('all', 'artist', 'studio_owner')),
  is_legal_update boolean not null default false,
  published_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);
create index if not exists app_changelog_published_idx on public.app_changelog (published_at desc);

alter table public.app_changelog enable row level security;
drop policy if exists "changelog: everyone reads" on public.app_changelog;
create policy "changelog: everyone reads" on public.app_changelog for select using (published_at <= now());
-- No insert/update/delete policies: admins write through the functions below.

-- The terms version everyone must have accepted. The app ships a version too and asks for
-- whichever is newer.
create table if not exists public.app_terms (
  id boolean primary key default true check (id),
  version text not null,
  updated_at timestamptz not null default now()
);
-- 2026-09-26: terms, privacy, refunds, studio agreement and guidelines updated (check-in, cash
-- refunds, fee collection, promotions, moderation) – everyone accepts again.
insert into public.app_terms (id, version) values (true, '2026-09-26')
  on conflict (id) do update set version = greatest(public.app_terms.version, excluded.version), updated_at = now();
alter table public.app_terms enable row level security;
drop policy if exists "terms: everyone reads" on public.app_terms;
create policy "terms: everyone reads" on public.app_terms for select using (true);

create or replace function public.current_terms_version()
returns text language sql stable security definer set search_path = public as $$
  select version from public.app_terms where id;
$$;
grant execute on function public.current_terms_version() to anon, authenticated;

-- Accepting records the version and time. Accepting an older version than the current one is refused.
create or replace function public.accept_terms(p_version text)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles;
begin
  if coalesce(trim(p_version), '') = '' then raise exception 'Missing terms version.'; end if;
  if p_version < public.current_terms_version() then
    raise exception 'Please update the app to read and accept the latest terms.';
  end if;
  update public.profiles set accepted_terms_version = p_version, accepted_terms_at = now()
  where id = auth.uid();
  p := (select x from public.profiles x where x.id = auth.uid());
  if p.id is null then raise exception 'not_found'; end if;
  return p;
end;
$$;

-- Admin: publish an entry. A legal update bumps the terms version (to today's date, or a later
-- one if today's was already used), so everyone is asked to accept again.
create or replace function public.admin_publish_changelog(p_version text, p_title text, p_body text,
  p_audience text default 'all', p_legal_update boolean default false)
returns public.app_changelog
language plpgsql security definer set search_path = public
as $$
declare
  v_entry public.app_changelog;
  v_terms text;
begin
  perform public.require_admin();
  if coalesce(trim(p_title), '') = '' then raise exception 'Give the update a title.'; end if;
  if p_legal_update then
    v_terms := to_char(now() at time zone 'utc', 'YYYY-MM-DD');
    if v_terms <= public.current_terms_version() then
      v_terms := public.current_terms_version() || '.' || to_char(clock_timestamp(), 'HH24MISS');
    end if;
    update public.app_terms set version = v_terms, updated_at = now() where id;
  end if;
  v_entry.id := gen_random_uuid();
  insert into public.app_changelog (id, version, title, body, audience, is_legal_update, created_by)
  values (v_entry.id, coalesce(nullif(trim(p_version), ''), coalesce(v_terms, to_char(now(), 'YYYY-MM-DD'))),
          trim(p_title), coalesce(p_body, ''), coalesce(p_audience, 'all'), p_legal_update, auth.uid());
  v_entry := (select x from public.app_changelog x where x.id = v_entry.id);
  return v_entry;
end;
$$;

create or replace function public.admin_delete_changelog(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  delete from public.app_changelog where id = p_id;
end;
$$;

-- How many users have accepted the current terms (for the admin dashboard).
create view public.admin_terms_status with (security_invoker = true) as
  select public.current_terms_version() as version,
         count(*) filter (where p.accepted_terms_version >= public.current_terms_version()) as accepted,
         count(*) filter (where p.role <> 'admin') as total
  from public.profiles p
  where public.is_trusted() and p.role <> 'admin';
