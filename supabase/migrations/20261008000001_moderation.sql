-- EasySesh: moderation tools for admins.
--  • Warnings: shown to the user in the app until they acknowledge them.
--  • Suspensions and bans for a chosen period (1, 3, 7 days or custom) or indefinitely.
--    They lift automatically when the period ends.
--  • A moderation history per user and studio (warnings, suspensions, bans, reports).

alter table public.profiles add column if not exists status_until timestamptz;
alter table public.studios add column if not exists suspended_until timestamptz;

-- Users can never change these themselves.
create or replace function public.guard_profile_moderation()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then new.status_until := old.status_until; end if;
  return new;
end;
$$;
drop trigger if exists guard_profile_moderation on public.profiles;
create trigger guard_profile_moderation before update on public.profiles
  for each row execute function public.guard_profile_moderation();

create or replace function public.guard_studio_moderation()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then new.suspended_until := null; else new.suspended_until := old.suspended_until; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists guard_studio_moderation on public.studios;
create trigger guard_studio_moderation before insert or update on public.studios
  for each row execute function public.guard_studio_moderation();

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  studio_id uuid references public.studios (id) on delete set null,
  -- warning | suspension | ban | lifted
  action text not null check (action in ('warning', 'suspension', 'ban', 'lifted')),
  reason text not null default '',
  ends_at timestamptz,
  acknowledged_at timestamptz,
  actor_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists moderation_actions_user_idx on public.moderation_actions (user_id, created_at desc);
create index if not exists moderation_actions_studio_idx on public.moderation_actions (studio_id, created_at desc);

alter table public.moderation_actions enable row level security;
drop policy if exists "moderation: own or admin" on public.moderation_actions;
create policy "moderation: own or admin" on public.moderation_actions for select
  using (user_id = auth.uid() or public.is_trusted());

-- Admin: warn a user (and optionally name the studio it's about).
create or replace function public.admin_warn(p_user_id uuid, p_reason text, p_studio_id uuid default null)
returns public.moderation_actions
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.moderation_actions;
begin
  perform public.require_admin();
  if coalesce(trim(p_reason), '') = '' then raise exception 'Write what the warning is about.'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then raise exception 'not_found'; end if;
  v_row.id := gen_random_uuid();
  insert into public.moderation_actions (id, user_id, studio_id, action, reason, actor_id)
  values (v_row.id, p_user_id, p_studio_id, 'warning', trim(p_reason), auth.uid());
  v_row := (select x from public.moderation_actions x where x.id = v_row.id);
  perform public.notify(p_user_id, 'system', 'Warning from EasySesh', trim(p_reason), null, null, p_studio_id);
  return v_row;
end;
$$;

-- Admin: suspend or ban an account for p_days days (null = until lifted), or lift it.
-- p_action: 'suspend' | 'ban' | 'lift'. Fractions of a day are allowed (0.5 = 12 hours).
create or replace function public.admin_moderate_user(p_user_id uuid, p_action text, p_days numeric default null, p_reason text default null)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles;
  v_until timestamptz := case when p_days is null then null else now() + make_interval(secs => (p_days * 86400)::double precision) end;
begin
  perform public.require_admin();
  if p_user_id = auth.uid() then raise exception 'You cannot change your own status.'; end if;
  if p_action not in ('suspend', 'ban', 'lift') then raise exception 'Unknown action.'; end if;
  if p_days is not null and p_days <= 0 then raise exception 'Choose a period longer than zero.'; end if;

  if p_action = 'lift' then
    update public.profiles set status = 'active', status_until = null, status_reason = null where id = p_user_id;
    p := (select x from public.profiles x where x.id = p_user_id);
    if p.id is null then raise exception 'not_found'; end if;
    update public.studios set is_active = true where owner_id = p_user_id and status = 'approved';
    insert into public.moderation_actions (user_id, action, reason, actor_id) values (p_user_id, 'lifted', coalesce(p_reason, ''), auth.uid());
    perform public.notify(p_user_id, 'system', 'Your account is active again', coalesce(nullif(trim(p_reason), ''), 'You can use EasySesh again.'), null, null, null);
    return p;
  end if;

  update public.profiles
     set status = case when p_action = 'ban' then 'banned'::public.account_status else 'suspended'::public.account_status end,
         status_until = v_until, status_reason = p_reason
   where id = p_user_id;
  p := (select x from public.profiles x where x.id = p_user_id);
  if p.id is null then raise exception 'not_found'; end if;
  update public.studios set is_active = false where owner_id = p_user_id;
  delete from public.device_tokens where user_id = p_user_id;
  insert into public.moderation_actions (user_id, action, reason, ends_at, actor_id)
  values (p_user_id, case when p_action = 'ban' then 'ban' else 'suspension' end, coalesce(p_reason, ''), v_until, auth.uid());
  return p;
end;
$$;

-- Admin: suspend a studio listing for a period (null = until lifted), or lift it.
create or replace function public.admin_moderate_studio(p_studio_id uuid, p_action text, p_days numeric default null, p_reason text default null)
returns public.studios
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios := (select x from public.studios x where x.id = p_studio_id);
  v_until timestamptz := case when p_days is null then null else now() + make_interval(secs => (p_days * 86400)::double precision) end;
begin
  perform public.require_admin();
  if s.id is null then raise exception 'not_found'; end if;
  if p_action not in ('suspend', 'lift') then raise exception 'Unknown action.'; end if;
  if p_days is not null and p_days <= 0 then raise exception 'Choose a period longer than zero.'; end if;

  if p_action = 'lift' then
    if s.status = 'suspended' then
      update public.studios set status = 'approved', is_active = true, suspended_until = null where id = s.id;
      insert into public.studio_status_events (studio_id, from_status, to_status, note, actor_id) values (s.id, 'suspended', 'approved', p_reason, auth.uid());
    end if;
    insert into public.moderation_actions (user_id, studio_id, action, reason, actor_id) values (s.owner_id, s.id, 'lifted', coalesce(p_reason, ''), auth.uid());
    perform public.notify(s.owner_id, 'system', 'Your studio is visible again', coalesce(nullif(trim(p_reason), ''), 'Artists can find and book your studio again.'), null, null, s.id);
  else
    update public.studios set status = 'suspended', is_active = false, suspended_until = v_until, admin_note = coalesce(p_reason, admin_note) where id = s.id;
    insert into public.studio_status_events (studio_id, from_status, to_status, note, actor_id) values (s.id, s.status, 'suspended', p_reason, auth.uid());
    insert into public.moderation_actions (user_id, studio_id, action, reason, ends_at, actor_id) values (s.owner_id, s.id, 'suspension', coalesce(p_reason, ''), v_until, auth.uid());
    perform public.notify(s.owner_id, 'system', 'Your studio has been suspended',
      coalesce(nullif(trim(p_reason), ''), 'Your studio breaks our rules.') ||
      case when v_until is null then ' It stays hidden until our team lifts the suspension.'
           else ' It is hidden until ' || to_char(v_until, 'DD Mon YYYY HH24:MI') || ' (UTC).' end,
      null, null, s.id);
  end if;
  return (select x from public.studios x where x.id = s.id);
end;
$$;

-- Ends suspensions and bans whose period is over. Runs every 5 minutes; users whose period just
-- ended can also trigger it for themselves when they sign in.
create or replace function public.lift_expired_moderation()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
  v_studio public.studios;
begin
  for v_user in select id from public.profiles where status <> 'active' and status_until is not null and status_until <= now() loop
    update public.profiles set status = 'active', status_until = null, status_reason = null where id = v_user;
    update public.studios set is_active = true where owner_id = v_user and status = 'approved';
    insert into public.moderation_actions (user_id, action, reason) values (v_user, 'lifted', 'Period ended');
  end loop;
  for v_studio in select * from public.studios where status = 'suspended' and suspended_until is not null and suspended_until <= now() loop
    update public.studios set status = 'approved', is_active = true, suspended_until = null where id = v_studio.id;
    insert into public.studio_status_events (studio_id, from_status, to_status, note) values (v_studio.id, 'suspended', 'approved', 'Suspension period ended');
    insert into public.moderation_actions (user_id, studio_id, action, reason) values (v_studio.owner_id, v_studio.id, 'lifted', 'Period ended');
    perform public.notify(v_studio.owner_id, 'system', 'Your studio is visible again', 'The suspension period has ended.', null, null, v_studio.id);
  end loop;
end;
$$;
revoke execute on function public.lift_expired_moderation() from public, anon, authenticated;

create or replace function public.lift_my_expired_restriction()
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles := (select x from public.profiles x where x.id = auth.uid());
begin
  if p.id is not null and p.status <> 'active' and p.status_until is not null and p.status_until <= now() then
    update public.profiles set status = 'active', status_until = null, status_reason = null where id = p.id;
    p := (select x from public.profiles x where x.id = p.id);
    update public.studios set is_active = true where owner_id = p.id and status = 'approved';
    insert into public.moderation_actions (user_id, action, reason) values (p.id, 'lifted', 'Period ended');
  end if;
  return p;
end;
$$;

-- The user confirms they've read a warning.
create or replace function public.acknowledge_warning(p_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.moderation_actions set acknowledged_at = now()
  where id = p_id and user_id = auth.uid() and acknowledged_at is null;
$$;

select cron.schedule('easysesh-lift-moderation', '*/5 * * * *', $$select public.lift_expired_moderation()$$);

-- Everything moderation-related for a user or their studio, newest first (admin dashboard).
create view public.admin_moderation_history with (security_invoker = true) as
select m.id, m.user_id, m.studio_id, m.action as kind, m.reason as details, m.ends_at, m.acknowledged_at,
       m.created_at, ap.email as actor_email
  from public.moderation_actions m
  left join public.profiles ap on ap.id = m.actor_id
union all
select r.id, case when r.target_type = 'user' then r.target_id else s.owner_id end,
       case when r.target_type = 'studio' then r.target_id end,
       'report' as kind, r.reason::text || coalesce(': ' || nullif(r.details, ''), '') || coalesce(' → ' || r.status::text || coalesce(' (' || r.admin_note || ')', ''), ''),
       null, null, r.created_at, null
  from public.reports r
  left join public.studios s on r.target_type = 'studio' and s.id = r.target_id
 where r.target_type in ('user', 'studio')
union all
select e.id, s.owner_id, e.studio_id, 'studio_status' as kind,
       coalesce(e.from_status::text, '–') || ' → ' || e.to_status::text || coalesce(': ' || e.note, ''),
       null, null, e.created_at, ap.email
  from public.studio_status_events e
  join public.studios s on s.id = e.studio_id
  left join public.profiles ap on ap.id = e.actor_id;

-- The users list gains the end of the current suspension and a count of warnings.
drop view if exists public.admin_users;
create view public.admin_users with (security_invoker = true) as
select p.id, p.email, p.role, p.status, p.status_reason, p.status_until, p.is_verified, p.created_at,
  a.artist_name, a.city as artist_city,
  s.id as studio_id, s.name as studio_name,
  coalesce(a.has_admin_badge, s.has_admin_badge, false) as has_admin_badge,
  (select count(*) from public.bookings b where b.artist_id = p.id) as booking_count,
  (select count(*) from public.moderation_actions m where m.user_id = p.id and m.action = 'warning') as warning_count
from public.profiles p
left join public.artist_profiles a on a.id = p.id
left join public.studios s on s.owner_id = p.id;
