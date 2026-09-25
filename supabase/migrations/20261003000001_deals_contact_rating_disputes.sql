-- EasySesh: per-studio platform fee (special deals), email + phone required in applications,
-- and disputes of ratings (studios dispute artists' reviews, artists dispute studios' ratings).

-- ---------------------------------------------------------------------------
-- Special deals: each studio can have its own platform fee (default 10%), set by an admin.
-- ---------------------------------------------------------------------------
alter table public.studios
  add column if not exists platform_fee_percent smallint not null default 10 check (platform_fee_percent between 0 and 30);

create or replace function public.guard_studio_extras()
returns trigger language plpgsql as $$
begin
  if not public.is_trusted() then
    if tg_op = 'INSERT' then
      new.has_admin_badge := false;
      new.admin_tags := '{}';
      new.promoted_until := null;
      new.platform_fee_percent := 10;
    else
      new.has_admin_badge := old.has_admin_badge;
      new.admin_tags := old.admin_tags;
      new.promoted_until := old.promoted_until;
      new.platform_fee_percent := old.platform_fee_percent;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.admin_set_platform_fee(p_studio_id uuid, p_percent integer)
returns public.studios
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  if p_percent is null or p_percent not between 0 and 30 then raise exception 'The platform fee must be between 0 and 30%%.'; end if;
  update public.studios set platform_fee_percent = p_percent where id = p_studio_id;
  if not found then raise exception 'not_found'; end if;
  return (select s from public.studios s where s.id = p_studio_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Applications need both an email address and a phone number.
-- ---------------------------------------------------------------------------
create or replace function public.studio_validation_problems(s public.studios)
returns text[]
language plpgsql stable
as $$
declare
  problems text[] := '{}';
begin
  if char_length(trim(s.name)) < 3 then problems := array_append(problems, 'Add your studio''s name.'::text); end if;
  if char_length(s.description) < 40 then problems := array_append(problems, 'Write a description of at least 40 characters.'::text); end if;
  if cardinality(s.photo_urls) = 0 then problems := array_append(problems, 'Add at least one photo.'::text); end if;
  if coalesce(s.address ->> 'street', '') = '' or coalesce(s.address ->> 'city', '') = '' then problems := array_append(problems, 'Add the studio''s address.'::text); end if;
  if s.latitude = 0 and s.longitude = 0 then problems := array_append(problems, 'Place your studio on the map.'::text); end if;
  if coalesce(s.contact ->> 'email', '') !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then problems := array_append(problems, 'Add a valid email address.'::text); end if;
  if length(regexp_replace(coalesce(s.contact ->> 'phone', ''), '[^0-9]', '', 'g')) < 6 then problems := array_append(problems, 'Add a phone number.'::text); end if;
  if jsonb_array_length(s.session_types) = 0 or exists (
       select 1 from jsonb_array_elements(s.session_types) as t where coalesce((t.value ->> 'hourly_rate')::int, 0) <= 0) then
    problems := array_append(problems, 'Set a price for each session type.'::text);
  end if;
  if not exists (select 1 from jsonb_array_elements(s.opening_hours) as h where not coalesce((h.value ->> 'is_closed')::boolean, false)) then
    problems := array_append(problems, 'Set your opening hours.'::text);
  end if;
  if cardinality(s.genres) = 0 then problems := array_append(problems, 'Pick at least one genre.'::text); end if;
  return problems;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rating disputes
-- ---------------------------------------------------------------------------
alter table public.artist_reviews add column if not exists is_hidden boolean not null default false;

create table if not exists public.rating_disputes (
  id uuid primary key default gen_random_uuid(),
  review_type text not null check (review_type in ('studio_review', 'artist_review')),
  review_id uuid not null,
  opened_by uuid not null references public.profiles (id) on delete cascade,
  reason text not null check (char_length(reason) between 10 and 1000),
  status text not null default 'open' check (status in ('open', 'removed', 'kept')),
  admin_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (review_type, review_id)
);
alter table public.rating_disputes enable row level security;
drop policy if exists "rating_disputes: own or admin read" on public.rating_disputes;
create policy "rating_disputes: own or admin read" on public.rating_disputes for select
  using (opened_by = auth.uid() or public.is_admin());

create or replace function public.refresh_artist_rating(p_artist_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.artist_profiles a set
    rating_average = coalesce((select round(avg(r.rating)::numeric, 2) from public.artist_reviews r where r.artist_id = a.id and not r.is_hidden), 0),
    review_count = (select count(*) from public.artist_reviews r where r.artist_id = a.id and not r.is_hidden)
  where a.id = p_artist_id;
$$;
revoke execute on function public.refresh_artist_rating from public, anon, authenticated;

-- The rated party disputes a rating: the studio (review of its studio) or the artist (rating by a studio).
create or replace function public.dispute_rating(p_review_type text, p_review_id uuid, p_reason text)
returns public.rating_disputes
language plpgsql security definer set search_path = public
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_allowed boolean;
  v_id uuid := gen_random_uuid();
begin
  if char_length(v_reason) < 10 then raise exception 'Tell us why the rating is unfair (at least 10 characters).'; end if;
  v_allowed := case p_review_type
    when 'studio_review' then exists (select 1 from public.reviews r where r.id = p_review_id and public.owns_studio(r.studio_id))
    when 'artist_review' then exists (select 1 from public.artist_reviews r where r.id = p_review_id and r.artist_id = auth.uid())
    else false end;
  if not v_allowed then raise exception 'forbidden' using errcode = '42501'; end if;
  if exists (select 1 from public.rating_disputes d where d.review_type = p_review_type and d.review_id = p_review_id) then
    raise exception 'This rating has already been disputed.';
  end if;
  insert into public.rating_disputes (id, review_type, review_id, opened_by, reason)
  values (v_id, p_review_type, p_review_id, auth.uid(), left(v_reason, 1000));
  return (select d from public.rating_disputes d where d.id = v_id);
end;
$$;

-- Admin decides: remove the rating (hidden and no longer counted) or keep it.
create or replace function public.admin_resolve_rating_dispute(p_dispute_id uuid, p_remove boolean, p_note text default null)
returns public.rating_disputes
language plpgsql security definer set search_path = public
as $$
declare
  v_dispute public.rating_disputes := (select d from public.rating_disputes d where d.id = p_dispute_id);
  v_artist uuid;
begin
  perform public.require_admin();
  if v_dispute.id is null then raise exception 'not_found'; end if;
  if v_dispute.status <> 'open' then raise exception 'This dispute is already resolved.'; end if;
  if p_remove then
    if v_dispute.review_type = 'studio_review' then
      update public.reviews set is_hidden = true where id = v_dispute.review_id;
    else
      update public.artist_reviews set is_hidden = true where id = v_dispute.review_id;
      v_artist := (select r.artist_id from public.artist_reviews r where r.id = v_dispute.review_id);
      perform public.refresh_artist_rating(v_artist);
    end if;
  end if;
  update public.rating_disputes set status = case when p_remove then 'removed' else 'kept' end,
    admin_note = nullif(btrim(coalesce(p_note, '')), ''), resolved_at = now()
  where id = p_dispute_id;
  perform public.notify(v_dispute.opened_by, 'system',
    case when p_remove then 'Rating removed' else 'Rating dispute reviewed' end,
    case when p_remove then 'We reviewed your dispute and removed the rating.'
         else 'We reviewed your dispute and the rating stays.' end || coalesce(' ' || nullif(btrim(p_note), ''), ''));
  return (select d from public.rating_disputes d where d.id = p_dispute_id);
end;
$$;

-- Admin list with the rating's content.
drop view if exists public.admin_rating_disputes;
create view public.admin_rating_disputes with (security_invoker = true) as
select d.*,
  coalesce(sr.rating, ar.rating) as rating,
  coalesce(sr.text, ar.text) as review_text,
  case when d.review_type = 'studio_review' then sr.artist_name else ar.studio_name end as reviewer_name,
  case when d.review_type = 'studio_review' then st.name else ap.artist_name end as rated_name
from public.rating_disputes d
left join public.reviews sr on d.review_type = 'studio_review' and sr.id = d.review_id
left join public.studios st on st.id = sr.studio_id
left join public.artist_reviews ar on d.review_type = 'artist_review' and ar.id = d.review_id
left join public.artist_profiles ap on ap.id = ar.artist_id;
