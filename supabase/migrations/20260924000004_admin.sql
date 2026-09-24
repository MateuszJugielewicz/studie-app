-- Sonora: admin dashboard RPCs. Every function checks public.is_admin().

create or replace function public.require_admin()
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
end;
$$;

-- approve | reject | request_changes
create or replace function public.admin_review_studio(p_studio_id uuid, p_decision text, p_note text default null)
returns public.studios
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios;
  previous public.studio_status;
  next_status public.studio_status;
begin
  perform public.require_admin();
  select * into s from public.studios where id = p_studio_id for update;
  if s.id is null then raise exception 'not_found'; end if;
  previous := s.status;

  next_status := case p_decision
    when 'approve' then 'approved'::public.studio_status
    when 'reject' then 'rejected'::public.studio_status
    when 'request_changes' then 'changes_requested'::public.studio_status
  end;
  if next_status is null then raise exception 'Unknown decision %', p_decision; end if;
  if next_status <> 'approved' and coalesce(trim(p_note), '') = '' then
    raise exception 'Add a note explaining what the studio should change.';
  end if;

  update public.studios set
    status = next_status,
    is_active = (next_status = 'approved'),
    is_verified = case when next_status = 'approved' then true else is_verified end,
    admin_note = p_note,
    reviewed_at = now(),
    reviewed_by = auth.uid()
  where id = s.id
  returning * into s;

  insert into public.studio_status_events (studio_id, from_status, to_status, note, actor_id)
  values (s.id, previous, next_status, p_note, auth.uid());
  return s;
end;
$$;

create or replace function public.admin_set_studio_state(p_studio_id uuid, p_active boolean default null, p_verified boolean default null, p_suspended boolean default null, p_note text default null)
returns public.studios
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios;
begin
  perform public.require_admin();
  select * into s from public.studios where id = p_studio_id for update;
  if s.id is null then raise exception 'not_found'; end if;

  if p_suspended is true and s.status <> 'suspended' then
    update public.studios set status = 'suspended', is_active = false, admin_note = coalesce(p_note, admin_note) where id = s.id;
    insert into public.studio_status_events (studio_id, from_status, to_status, note, actor_id) values (s.id, s.status, 'suspended', p_note, auth.uid());
  elsif p_suspended is false and s.status = 'suspended' then
    update public.studios set status = 'approved', admin_note = coalesce(p_note, admin_note) where id = s.id;
    insert into public.studio_status_events (studio_id, from_status, to_status, note, actor_id) values (s.id, 'suspended', 'approved', p_note, auth.uid());
  end if;
  if p_active is not null then
    update public.studios set is_active = p_active and status = 'approved' where id = s.id;
  end if;
  if p_verified is not null then
    update public.studios set is_verified = p_verified where id = s.id;
  end if;
  select * into s from public.studios where id = p_studio_id;
  return s;
end;
$$;

-- active | suspended | banned. Suspending a studio owner also hides their studio.
create or replace function public.admin_set_user_status(p_user_id uuid, p_status public.account_status, p_reason text default null)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles;
begin
  perform public.require_admin();
  if p_user_id = auth.uid() then raise exception 'You cannot change your own status.'; end if;
  update public.profiles set status = p_status, status_reason = p_reason where id = p_user_id returning * into p;
  if p.id is null then raise exception 'not_found'; end if;
  if p_status <> 'active' then
    update public.studios set is_active = false where owner_id = p_user_id;
    delete from public.device_tokens where user_id = p_user_id;
  end if;
  return p;
end;
$$;

create or replace function public.admin_verify_user(p_user_id uuid, p_verified boolean)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles;
begin
  perform public.require_admin();
  update public.profiles set is_verified = p_verified where id = p_user_id returning * into p;
  update public.artist_profiles set is_verified = p_verified where id = p_user_id;
  return p;
end;
$$;

create or replace function public.admin_resolve_report(p_report_id uuid, p_status public.report_status, p_note text default null)
returns public.reports
language plpgsql security definer set search_path = public
as $$
declare
  r public.reports;
begin
  perform public.require_admin();
  update public.reports set status = p_status, admin_note = p_note, resolved_at = case when p_status = 'open' then null else now() end
  where id = p_report_id returning * into r;
  return r;
end;
$$;

create or replace function public.admin_set_review_hidden(p_review_id uuid, p_hidden boolean)
returns public.reviews
language plpgsql security definer set search_path = public
as $$
declare
  r public.reviews;
begin
  perform public.require_admin();
  update public.reviews set is_hidden = p_hidden where id = p_review_id returning * into r;
  return r;
end;
$$;

-- Closes a dispute. Money movements (refunds) are done through the admin-refund edge function first.
create or replace function public.admin_resolve_dispute(p_dispute_id uuid, p_resolution text, p_booking_status public.booking_status default 'completed')
returns public.disputes
language plpgsql security definer set search_path = public
as $$
declare
  d public.disputes;
begin
  perform public.require_admin();
  update public.disputes set status = 'resolved', resolution = p_resolution, resolved_at = now() where id = p_dispute_id returning * into d;
  if d.id is null then raise exception 'not_found'; end if;
  update public.bookings set status = p_booking_status, changed_by = auth.uid() where id = d.booking_id and status = 'disputed';
  return d;
end;
$$;

-- Numbers for the admin overview. Revenue figures are in minor units per currency.
create or replace function public.admin_dashboard_stats(p_from timestamptz default now() - interval '30 days', p_to timestamptz default now())
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.require_admin();
  select jsonb_build_object(
    'artists', (select count(*) from public.profiles where role = 'artist'),
    'studio_owners', (select count(*) from public.profiles where role = 'studio_owner'),
    'studios_live', (select count(*) from public.studios where status = 'approved' and is_active),
    'studios_pending', (select count(*) from public.studios where status = 'pending_review'),
    'bookings_total', (select count(*) from public.bookings where created_at between p_from and p_to and status <> 'awaiting_payment'),
    'bookings_confirmed', (select count(*) from public.bookings where created_at between p_from and p_to and status in ('confirmed', 'completed')),
    'bookings_cancelled', (select count(*) from public.bookings where created_at between p_from and p_to and status in ('cancelled', 'declined')),
    'booking_rate', (
      select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where status in ('confirmed', 'completed', 'disputed')) / count(*), 1) end
      from public.bookings where created_at between p_from and p_to
    ),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'open_disputes', (select count(*) from public.disputes where status = 'open'),
    'failed_payments', (select count(*) from public.transactions where status = 'failed' and created_at between p_from and p_to),
    -- Per currency. Platform earnings = 10% platform fee on completed sessions (card and cash).
    'revenue', coalesce((
      select jsonb_object_agg(currency, jsonb_build_object(
        'gross', card_volume + cash_volume, 'card', card_volume, 'cash', cash_volume,
        'platform', platform, 'refunds', refunds, 'fees_owed', fees_owed))
      from (
        select c.currency,
          coalesce((select sum((b.price ->> 'total')::int) from public.bookings b
                    where b.status = 'completed' and b.price ->> 'currency' = c.currency and b.ends_at between p_from and p_to
                      and b.payment_method is distinct from 'cash'), 0) as card_volume,
          coalesce((select sum((b.price ->> 'total')::int) from public.bookings b
                    where b.status = 'completed' and b.price ->> 'currency' = c.currency and b.ends_at between p_from and p_to
                      and b.payment_method = 'cash'), 0) as cash_volume,
          coalesce((select sum((b.price ->> 'studio_commission')::int + (b.price ->> 'service_fee')::int) from public.bookings b
                    where b.status = 'completed' and b.price ->> 'currency' = c.currency and b.ends_at between p_from and p_to), 0) as platform,
          coalesce((select sum(t.amount) from public.transactions t
                    where t.kind = 'refund' and t.status = 'succeeded' and t.currency = c.currency and t.created_at between p_from and p_to), 0) as refunds,
          coalesce((select sum(l.amount) from public.studio_fee_ledger l where l.currency = c.currency), 0) as fees_owed
        from (select distinct price ->> 'currency' as currency from public.bookings where status = 'completed') c
      ) x
    ), '{}'::jsonb),
    'top_studios', coalesce((
      select jsonb_agg(row_to_json(x)) from (
        select s.id, s.name, s.address ->> 'city' as city, count(b.id) as bookings, s.rating_average as rating
        from public.studios s join public.bookings b on b.studio_id = s.id
        where b.created_at between p_from and p_to and b.status in ('confirmed', 'completed')
        group by s.id order by count(b.id) desc limit 10
      ) x
    ), '[]'::jsonb),
    'top_areas', coalesce((
      select jsonb_agg(row_to_json(x)) from (
        select s.address ->> 'city' as city, nullif(s.address ->> 'area', '') as area, count(b.id) as bookings
        from public.studios s join public.bookings b on b.studio_id = s.id
        where b.created_at between p_from and p_to and b.status in ('confirmed', 'completed')
        group by 1, 2 order by count(b.id) desc limit 10
      ) x
    ), '[]'::jsonb),
    'bookings_per_day', coalesce((
      select jsonb_agg(row_to_json(x) order by x.day) from (
        select date_trunc('day', created_at)::date as day, count(*) as bookings
        from public.bookings where created_at between p_from and p_to and status <> 'awaiting_payment'
        group by 1
      ) x
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

-- Admin-only view of users with their artist/studio info.
create or replace view public.admin_users with (security_invoker = true) as
select p.id, p.email, p.role, p.status, p.status_reason, p.is_verified, p.created_at,
  a.artist_name, a.city as artist_city,
  s.id as studio_id, s.name as studio_name,
  (select count(*) from public.bookings b where b.artist_id = p.id) as booking_count
from public.profiles p
left join public.artist_profiles a on a.id = p.id
left join public.studios s on s.owner_id = p.id;
