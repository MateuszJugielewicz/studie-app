-- Security hardening, found by supabase/tests/attacks.sql.

-- 1. Studio listings must have sane prices and settings, also after approval (the checks in
--    submit_studio_for_review only run once). A negative add-on price made the booking total and
--    EasySesh's fee negative, which for cash bookings would be credited to the studio.
--    Drafts may still have a price of 0 while the owner is filling them in.
create or replace function public.validate_studio_listing()
returns trigger
language plpgsql set search_path = public
as $$
declare
  v jsonb;
  p jsonb := coalesce(new.booking_policy, '{}'::jsonb);
  listed boolean := new.status in ('pending_review', 'approved', 'suspended');
begin
  for v in select x from jsonb_array_elements(coalesce(new.session_types, '[]'::jsonb)) as x loop
    if coalesce((v ->> 'hourly_rate')::numeric, 0) < 0 or coalesce((v ->> 'hourly_rate')::numeric, 0) > 10000000
       or (listed and coalesce((v ->> 'hourly_rate')::numeric, 0) = 0) then
      raise exception 'Session prices must be more than 0.' using errcode = '23514';
    end if;
    if coalesce((v ->> 'minimum_hours')::numeric, 1) not between 1 and 12 then
      raise exception 'Minimum hours must be between 1 and 12.' using errcode = '23514';
    end if;
  end loop;
  for v in select x from jsonb_array_elements(coalesce(new.add_ons, '[]'::jsonb)) as x loop
    if coalesce((v ->> 'price')::numeric, 0) not between 0 and 10000000 then
      raise exception 'Add-on prices can''t be negative.' using errcode = '23514';
    end if;
  end loop;
  if coalesce((p ->> 'deposit_percent')::numeric, 0) not between 0 and 100
     or coalesce((p ->> 'minimum_notice_hours')::numeric, 0) not between 0 and 720
     or coalesce((p ->> 'max_advance_days')::numeric, 90) not between 1 and 730
     or coalesce((p ->> 'buffer_minutes')::numeric, 0) not between 0 and 480 then
    raise exception 'Booking settings are out of range.' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Named so it runs after the guard_* triggers (alphabetical), i.e. on the row that gets written.
drop trigger if exists validate_studio_listing on public.studios;
create trigger validate_studio_listing before insert or update on public.studios
  for each row execute function public.validate_studio_listing();

-- 2. Backstop: no booking can be stored with a negative price, payout or fee, whatever the listing says.
--    NOT VALID keeps existing rows untouched; every new or changed booking is checked.
alter table public.bookings drop constraint if exists bookings_price_not_negative;
alter table public.bookings add constraint bookings_price_not_negative check (
  coalesce((price ->> 'total')::numeric, 0) >= 0
  and coalesce((price ->> 'subtotal')::numeric, 0) >= 0
  and coalesce((price ->> 'studio_commission')::numeric, 0) >= 0
  and coalesce((price ->> 'studio_payout')::numeric, 0) >= 0
  and coalesce((price ->> 'due_now')::numeric, 0) >= 0
) not valid;

-- 3. Scheduler and internal helpers: only pg_cron and other database functions may run them.
--    (Calling them early did no damage, but nobody outside needs them; is_blocked_between also
--    told anyone whether two people had blocked each other.)
revoke execute on function public.run_booking_housekeeping() from public, anon, authenticated;
revoke execute on function public.run_cash_housekeeping() from public, anon, authenticated;
revoke execute on function public.queue_session_reminders() from public, anon, authenticated;
revoke execute on function public.refresh_studio_rating(uuid) from public, anon, authenticated;
revoke execute on function public.is_blocked_between(uuid, uuid) from public, anon, authenticated;

-- 4. Push tokens go into the URL of Apple's / Google's push API, so only allow what real tokens look
--    like (APNs: hex, FCM: letters, digits, ':', '_' and '-').
alter table public.device_tokens drop constraint if exists device_tokens_token_format;
alter table public.device_tokens add constraint device_tokens_token_format
  check (token ~ '^[A-Za-z0-9:_-]{16,4096}$' and platform in ('ios', 'android')) not valid;
