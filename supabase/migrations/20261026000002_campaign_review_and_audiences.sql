-- Campaigns need a review before they can be sent, and can start from a template whose recipients
-- are found in the database (e.g. artists who never finished their profile).
--
-- Review: any admin (rank admin or owner) can read campaigns and approve one. Changing what gets
-- sent (sender, subject, message, small print) or adding recipients clears the approval, so what
-- goes out is always exactly what someone approved. admin-campaign-send refuses unapproved batches.

alter table public.email_campaigns add column if not exists template text;
alter table public.email_campaigns add column if not exists reviewed_by uuid references public.profiles (id) on delete set null;
alter table public.email_campaigns add column if not exists reviewed_at timestamptz;

-- Admins can read campaigns (to review them); writing stays with owners ("…: owners" policies).
create policy "email_campaigns: admins read" on public.email_campaigns for select using (public.has_admin_rank('admin'));
create policy "email_campaign_recipients: admins read" on public.email_campaign_recipients for select using (public.has_admin_rank('admin'));

-- Edits clear the approval (the review columns can only be set through review_email_campaign).
create or replace function public.touch_email_campaign()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if (new.from_local, new.subject, new.body, new.footer) is distinct from (old.from_local, old.subject, old.body, old.footer) then
    new.reviewed_by := null;
    new.reviewed_at := null;
  elsif (new.reviewed_by, new.reviewed_at) is distinct from (old.reviewed_by, old.reviewed_at)
        and coalesce(current_setting('easysesh.reviewing', true), '') <> 'on' then
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

create or replace function public.clear_campaign_review_on_new_recipients()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('easysesh.reviewing', 'on', true);
  update public.email_campaigns set reviewed_by = null, reviewed_at = null
  where id = new.campaign_id and reviewed_at is not null;
  perform set_config('easysesh.reviewing', 'off', true);
  return new;
end;
$$;
create trigger clear_campaign_review_on_new_recipients after insert on public.email_campaign_recipients
  for each row execute function public.clear_campaign_review_on_new_recipients();

-- An admin approves (or withdraws approval of) the campaign as it is now.
create or replace function public.review_email_campaign(p_campaign_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_rows integer;
begin
  if not public.has_admin_rank('admin') then
    raise exception 'Only admins can review campaigns.' using errcode = '42501';
  end if;
  perform set_config('easysesh.reviewing', 'on', true);
  update public.email_campaigns
  set reviewed_by = case when p_approve then auth.uid() end,
      reviewed_at = case when p_approve then now() end
  where id = p_campaign_id;
  get diagnostics v_rows = row_count;
  perform set_config('easysesh.reviewing', 'off', true);
  if v_rows = 0 then raise exception 'Campaign not found.'; end if;
end;
$$;
revoke execute on function public.review_email_campaign(uuid, boolean) from public, anon;
grant execute on function public.review_email_campaign(uuid, boolean) to authenticated;

-- New columns go at the end (create or replace view can only append).
create or replace view public.admin_email_campaigns with (security_invoker = true) as
select c.id, c.name, c.from_local, c.subject, c.body, c.footer, c.note, c.status, c.created_by, c.created_at, c.updated_at,
  count(r.id) filter (where r.status = 'pending') as pending_count,
  count(r.id) filter (where r.status = 'sent') as sent_count,
  count(r.id) filter (where r.status = 'failed') as failed_count,
  count(r.id) filter (where r.status = 'skipped') as skipped_count,
  c.template, c.reviewed_by, c.reviewed_at, rv.email as reviewed_by_email
from public.email_campaigns c
left join public.profiles rv on rv.id = c.reviewed_by
left join public.email_campaign_recipients r on r.campaign_id = c.id
group by c.id, rv.email;
grant select on public.admin_email_campaigns to authenticated;
revoke all on public.admin_email_campaigns from anon;

-- Who a template goes to. Only active, non-staff accounts with a real address, that haven't turned
-- off emails (settings.email_enabled) and aren't on the do-not-contact list. "Come back" emails to
-- artists are marketing, so they also need settings.marketing = true (off by default).
-- Columns: email, name ({{name}}), city ({{city}}), website ({{website}} = the link the email points to).
create or replace function public.campaign_audience(p_template text)
returns table (email text, name text, city text, website text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.has_admin_rank('owner') then
    raise exception 'Only owners can build campaign lists.' using errcode = '42501';
  end if;
  return query
  with people as (
    select p.* from public.profiles p
    where p.status = 'active' and p.role <> 'admin' and p.admin_rank is null
      and p.email not like '%.invalid'
      and coalesce((p.settings ->> 'email_enabled')::boolean, true)
      and not exists (select 1 from public.email_suppressions s where s.email = lower(p.email))
  )
  select lower(p.email), x.name, x.city, x.website
  from people p
  cross join lateral (
    select
      coalesce(nullif(btrim(a.artist_name), ''), nullif(btrim(st.name), ''), '') as name,
      coalesce(nullif(btrim(a.city), ''), nullif(btrim(st.address ->> 'city'), ''), '') as city,
      case p_template
        when 'artist_profile_unfinished' then 'https://easysesh.live/onboarding'
        when 'artist_no_recent_bookings' then 'https://easysesh.live/studios'
        when 'studio_setup_unfinished' then 'https://easysesh.live/studio/edit'
        when 'studio_changes_requested' then 'https://easysesh.live/studio/edit'
        when 'studio_no_recent_bookings' then 'https://easysesh.live/studios/' || st.id
        else 'https://easysesh.live'
      end as website,
      a.id as artist_id, st.id as studio_id, st.status as studio_status, st.created_at as studio_created
    from (select 1) one
    left join public.artist_profiles a on a.id = p.id
    left join lateral (select s.* from public.studios s where s.owner_id = p.id order by s.created_at limit 1) st on true
  ) x
  where case p_template
    -- Artists who signed up 2+ days ago and never finished their profile (name and city).
    when 'artist_profile_unfinished' then
      p.role = 'artist' and p.created_at < now() - interval '2 days'
      and (x.artist_id is null or exists (select 1 from public.artist_profiles a where a.id = p.id and (btrim(a.artist_name) = '' or btrim(a.city) = '')))
    -- Studio owners who signed up 2+ days ago whose studio was never sent for review.
    when 'studio_setup_unfinished' then
      p.role = 'studio_owner' and p.created_at < now() - interval '2 days'
      and (x.studio_id is null or x.studio_status::text = 'draft')
    -- Studios we asked to change something, still not resubmitted after 3 days.
    when 'studio_changes_requested' then
      p.role = 'studio_owner' and x.studio_status::text = 'changes_requested'
      and exists (select 1 from public.studios s where s.id = x.studio_id and coalesce(s.submitted_at, s.created_at) < now() - interval '3 days')
    -- Anyone who hasn't confirmed their email address after 2 days.
    when 'email_unverified' then
      p.email_verified_at is null and p.created_at < now() - interval '2 days'
    -- Artists with a finished profile, no booking in 60 days (or never, after 30 days), who said yes to marketing.
    when 'artist_no_recent_bookings' then
      p.role = 'artist' and coalesce((p.settings ->> 'marketing')::boolean, false)
      and exists (select 1 from public.artist_profiles a where a.id = p.id and btrim(a.artist_name) <> '' and btrim(a.city) <> '')
      and p.created_at < now() - interval '30 days'
      and not exists (select 1 from public.bookings b where b.artist_id = p.id and b.created_at > now() - interval '60 days')
    -- Approved, visible studios that haven't had a booking request in 30 days.
    when 'studio_no_recent_bookings' then
      p.role = 'studio_owner' and x.studio_status::text = 'approved'
      and x.studio_created < now() - interval '30 days'
      and exists (select 1 from public.studios s where s.id = x.studio_id and s.is_active)
      and not exists (select 1 from public.bookings b where b.studio_id = x.studio_id and b.created_at > now() - interval '30 days')
    else false
  end;
end;
$$;
revoke execute on function public.campaign_audience(text) from public, anon;
grant execute on function public.campaign_audience(text) to authenticated;
