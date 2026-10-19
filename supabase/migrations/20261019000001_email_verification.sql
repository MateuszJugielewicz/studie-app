-- Email verification, sent from noreply@easysesh.live by the email-verification edge function.
-- Supabase auto-confirms sign-ups (so auth.users.email_confirmed_at says nothing); our own flag is
-- profiles.email_verified_at. Unverified users can browse, but can't book, message, start chats,
-- review or submit a studio for approval. Apple/Google sign-ups are verified by the provider.

alter table public.profiles add column if not exists email_verified_at timestamptz;

-- Everyone who signed up before this counts as verified.
update public.profiles set email_verified_at = coalesce(created_at, now()) where email_verified_at is null;

-- One-time links. Only the SHA-256 of the token is stored; nobody but these functions can read it.
create table if not exists public.email_verification_tokens (
  token_hash text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists email_verification_tokens_user on public.email_verification_tokens (user_id, created_at desc);
alter table public.email_verification_tokens enable row level security;
revoke all on public.email_verification_tokens from public, anon, authenticated;

-- New profiles: verified straight away when the sign-up came from Apple/Google, otherwise not.
create or replace function public.set_initial_email_verification()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_provider text := (select u.raw_app_meta_data ->> 'provider' from auth.users u where u.id = new.id);
begin
  if new.email_verified_at is null and coalesce(v_provider, 'email') not in ('email', 'phone') then
    new.email_verified_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists set_initial_email_verification on public.profiles;
create trigger set_initial_email_verification before insert on public.profiles
  for each row execute function public.set_initial_email_verification();

-- ...and send the "Confirm your email" email (after commit, via pg_net).
create or replace function public.on_profile_created_send_verification()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.email_verified_at is null and coalesce(new.email, '') <> '' then
    perform public.call_edge_function('email-verification', jsonb_build_object('user_id', new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists send_email_verification on public.profiles;
create trigger send_email_verification after insert on public.profiles
  for each row execute function public.on_profile_created_send_verification();

-- Users can't mark themselves verified.
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
    new.stripe_customer_id := old.stripe_customer_id;
    new.accepted_terms_version := old.accepted_terms_version;
    new.accepted_terms_at := old.accepted_terms_at;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tokens (server only)
-- ---------------------------------------------------------------------------

-- Creates a link token for a user and returns it with their email, or null when they're already
-- verified or got one less than a minute ago (at most 10 a day).
create or replace function public.issue_email_verification(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  me public.profiles;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  select * into me from public.profiles where id = p_user_id;
  if me.id is null or me.email_verified_at is not null or coalesce(me.email, '') = '' then return null; end if;
  if exists (select 1 from public.email_verification_tokens t where t.user_id = me.id and t.created_at > now() - interval '1 minute')
     or (select count(*) from public.email_verification_tokens t where t.user_id = me.id and t.created_at > now() - interval '1 day') >= 10 then
    return null;
  end if;
  insert into public.email_verification_tokens (token_hash, user_id, expires_at)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), me.id, now() + interval '7 days');
  return jsonb_build_object(
    'token', v_token,
    'email', me.email,
    'role', me.role,
    'name', coalesce(nullif((select a.artist_name from public.artist_profiles a where a.id = me.id), ''), '')
  );
end;
$$;
revoke execute on function public.issue_email_verification(uuid) from public, anon, authenticated;

-- Signed-in user asks for a new link ("Resend email").
create or replace function public.resend_email_verification()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'Please sign in to continue.' using errcode = '42501'; end if;
  if me.email_verified_at is not null then return; end if;
  if exists (select 1 from public.email_verification_tokens t where t.user_id = me.id and t.created_at > now() - interval '1 minute') then
    raise exception 'We just sent you an email. Please wait a minute before asking for another one.';
  end if;
  perform public.call_edge_function('email-verification', jsonb_build_object('user_id', me.id));
end;
$$;
revoke execute on function public.resend_email_verification() from public, anon;
grant execute on function public.resend_email_verification() to authenticated;

-- The link in the email. Works without being signed in (the email may be opened on another device).
create or replace function public.verify_email(p_token text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return false; end if;
  update public.email_verification_tokens t set expires_at = now()
  where t.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') and t.expires_at > now()
  returning t.user_id into v_user;
  if v_user is null then return false; end if;
  update public.profiles set email_verified_at = coalesce(email_verified_at, now()) where id = v_user;
  -- Used up: the other links for this user stop working too.
  update public.email_verification_tokens set expires_at = now() where user_id = v_user and expires_at > now();
  return true;
end;
$$;
grant execute on function public.verify_email(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- What unverified users can't do
-- ---------------------------------------------------------------------------
create or replace function public.require_verified_email(p_user_id uuid)
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_user_id is not null
     and not exists (select 1 from public.profiles where id = p_user_id and email_verified_at is not null) then
    -- Default error code (not 42501), so the apps show this message instead of a generic "not allowed".
    raise exception 'Please verify your email address first. We sent you a link – check your inbox.';
  end if;
end;
$$;
revoke execute on function public.require_verified_email(uuid) from public, anon, authenticated;

create or replace function public.check_email_verified()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_table_name = 'bookings' then
    perform public.require_verified_email(new.artist_id);
  elsif tg_table_name = 'reviews' then
    perform public.require_verified_email(new.artist_id);
  elsif tg_table_name = 'messages' then
    if new.sender_id is not null and new.sender_id = auth.uid() then
      perform public.require_verified_email(new.sender_id);
    end if;
  elsif tg_table_name = 'conversations' then
    perform public.require_verified_email(auth.uid());
  elsif tg_table_name = 'studios' then
    -- Submitting the studio for approval.
    if new.status = 'pending_review' and old.status is distinct from 'pending_review' and auth.uid() is not null then
      perform public.require_verified_email(new.owner_id);
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function public.check_email_verified() from public, anon, authenticated;

drop trigger if exists check_email_verified on public.bookings;
create trigger check_email_verified before insert on public.bookings
  for each row execute function public.check_email_verified();
drop trigger if exists check_email_verified on public.reviews;
create trigger check_email_verified before insert on public.reviews
  for each row execute function public.check_email_verified();
drop trigger if exists check_email_verified on public.messages;
create trigger check_email_verified before insert on public.messages
  for each row execute function public.check_email_verified();
drop trigger if exists check_email_verified on public.conversations;
create trigger check_email_verified before insert on public.conversations
  for each row execute function public.check_email_verified();
drop trigger if exists check_email_verified on public.studios;
create trigger check_email_verified before update on public.studios
  for each row execute function public.check_email_verified();
