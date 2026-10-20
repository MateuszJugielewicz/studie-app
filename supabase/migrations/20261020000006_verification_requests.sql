-- Artists and studios apply for the verified badge; anyone on the EasySesh team (support and up)
-- reviews the application in the admin panel and grants or denies it with a note. The applicant
-- is notified either way, and a grant also shows up in their account history (audit trigger).
create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  studio_id uuid references public.studios (id) on delete cascade,  -- set for studio applications
  kind text not null check (kind in ('artist', 'studio')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied', 'cancelled')),
  message text not null default '' check (char_length(message) <= 2000),
  links text[] not null default '{}' check (cardinality(links) <= 6),
  staff_note text,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists verification_requests_one_pending on public.verification_requests (user_id, kind) where status = 'pending';
create index if not exists verification_requests_status on public.verification_requests (status, created_at);

alter table public.verification_requests enable row level security;
create policy "verification_requests: own or staff read" on public.verification_requests for select
  using (user_id = auth.uid() or public.is_admin());
-- Written only through the functions below.

-- Support staff may review applications (the write guard otherwise limits them to support tickets).
create or replace function public.staff_write_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null and public.admin_rank() = 'support'
     and tg_table_name not in ('support_tickets', 'support_messages')
     and not (tg_table_name = 'profiles' and tg_op = 'UPDATE' and to_jsonb(old) ->> 'id' = auth.uid()::text)
     and not (coalesce(current_setting('easysesh.verification_review', true), '') = 'on'
              and tg_table_name in ('profiles', 'artist_profiles', 'studios', 'verification_requests')) then
    raise exception 'Your admin rank (support) can only answer support requests.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Apply: artists for their artist profile, studio owners for their (approved) studio.
create or replace function public.request_verification(p_message text, p_links text[] default '{}')
returns public.verification_requests
language plpgsql security definer set search_path = public
as $$
declare
  v_role public.user_role := (select p.role from public.profiles p where p.id = auth.uid() and p.status = 'active');
  v_studio public.studios := (select s from public.studios s where s.owner_id = auth.uid() limit 1);
  v_links text[] := coalesce((select array_agg(left(btrim(l), 300)) from unnest(coalesce(p_links, '{}')) l where btrim(l) <> ''), '{}');
  v_row public.verification_requests;
begin
  perform public.require_verified_email(auth.uid());
  if char_length(btrim(coalesce(p_message, ''))) < 10 then
    raise exception 'Tell us a bit about yourself (at least 10 characters).';
  end if;
  if cardinality(v_links) > 6 then raise exception 'Add at most 6 links.'; end if;
  if v_role = 'artist' then
    if not exists (select 1 from public.artist_profiles a where a.id = auth.uid() and a.artist_name <> '') then
      raise exception 'Finish your artist profile first.';
    end if;
    if exists (select 1 from public.artist_profiles a where a.id = auth.uid() and a.is_verified) then
      raise exception 'You''re already verified.';
    end if;
    if exists (select 1 from public.verification_requests r where r.user_id = auth.uid() and r.kind = 'artist' and r.status = 'pending') then
      raise exception 'Your application is already waiting for review.';
    end if;
    insert into public.verification_requests (user_id, kind, message, links)
    values (auth.uid(), 'artist', left(btrim(p_message), 2000), v_links) returning * into v_row;
  elsif v_role = 'studio_owner' then
    if v_studio.id is null or v_studio.status <> 'approved' then
      raise exception 'Your studio must be approved before it can be verified.';
    end if;
    if v_studio.is_verified then raise exception 'Your studio is already verified.'; end if;
    if exists (select 1 from public.verification_requests r where r.user_id = auth.uid() and r.kind = 'studio' and r.status = 'pending') then
      raise exception 'Your application is already waiting for review.';
    end if;
    insert into public.verification_requests (user_id, studio_id, kind, message, links)
    values (auth.uid(), v_studio.id, 'studio', left(btrim(p_message), 2000), v_links) returning * into v_row;
  else
    raise exception 'Only artists and studios can apply.';
  end if;
  return v_row;
end;
$$;
revoke execute on function public.request_verification(text, text[]) from public, anon;
grant execute on function public.request_verification(text, text[]) to authenticated;

create or replace function public.cancel_verification_request(p_request_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.verification_requests set status = 'cancelled'
  where id = p_request_id and user_id = auth.uid() and status = 'pending';
end;
$$;
revoke execute on function public.cancel_verification_request(uuid) from public, anon;
grant execute on function public.cancel_verification_request(uuid) to authenticated;

-- Staff decision (support rank and up). A note is required to deny, and is shown to the applicant.
create or replace function public.admin_review_verification(p_request_id uuid, p_approve boolean, p_note text default null)
returns public.verification_requests
language plpgsql security definer set search_path = public
as $$
declare
  v_req public.verification_requests := (select r from public.verification_requests r where r.id = p_request_id for update);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform public.require_admin();
  if v_req.id is null then raise exception 'not_found'; end if;
  if v_req.status <> 'pending' then raise exception 'This application was already handled.'; end if;
  if not p_approve and v_note is null then raise exception 'Add a note explaining why the application is denied.'; end if;

  perform set_config('easysesh.verification_review', 'on', true);
  update public.verification_requests
  set status = case when p_approve then 'approved' else 'denied' end, staff_note = left(v_note, 1000),
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = v_req.id returning * into v_req;

  if p_approve then
    if v_req.kind = 'studio' then
      update public.studios set is_verified = true where id = v_req.studio_id;
    else
      update public.profiles set is_verified = true where id = v_req.user_id;
      update public.artist_profiles set is_verified = true where id = v_req.user_id;
    end if;
    perform public.notify(v_req.user_id, 'system',
      case when v_req.kind = 'studio' then 'Your studio is verified' else 'You''re verified' end,
      'Your verified badge is now shown on your ' || case when v_req.kind = 'studio' then 'studio page.' else 'artist profile.' end
        || coalesce(E'\n\n' || v_note, ''),
      null, null, v_req.studio_id);
  else
    perform public.notify(v_req.user_id, 'system', 'Verification not granted',
      'We couldn''t verify ' || case when v_req.kind = 'studio' then 'your studio' else 'your artist profile' end
        || E' this time.\n\n' || v_note || E'\n\nYou can apply again with more information.',
      null, null, v_req.studio_id);
  end if;
  perform set_config('easysesh.verification_review', '', true);
  return v_req;
end;
$$;
revoke execute on function public.admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_verification(uuid, boolean, text) to authenticated;

-- Admin panel list with the applicant's details.
create or replace view public.admin_verification_requests with (security_invoker = true) as
select r.*, p.email, p.role,
       coalesce(s.name, a.artist_name) as display_name,
       coalesce(s.photo_urls[1], a.avatar_url) as photo_url,
       a.city as artist_city, s.address ->> 'city' as studio_city,
       (select count(*) from public.bookings b where (r.kind = 'artist' and b.artist_id = r.user_id) or (r.kind = 'studio' and b.studio_id = r.studio_id)) as booking_count,
       rp.email as reviewed_by_email
from public.verification_requests r
join public.profiles p on p.id = r.user_id
left join public.studios s on s.id = r.studio_id
left join public.artist_profiles a on a.id = r.user_id
left join public.profiles rp on rp.id = r.reviewed_by;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_audit' and tgrelid = 'public.verification_requests'::regclass) then
    create trigger zz_staff_write_guard before insert or update or delete on public.verification_requests for each row execute function public.staff_write_guard();
    create trigger zz_staff_write_audit after insert or update or delete on public.verification_requests for each row execute function public.staff_write_audit();
  end if;
end $$;
