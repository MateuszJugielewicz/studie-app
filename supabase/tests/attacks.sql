-- Abuse tests: every block tries something a malicious user could do by calling the API directly
-- (the public anon key is in the apps, so anyone can). Each writes PASS when the attack is stopped,
-- VULNERABLE when it works. Run with: node run.mjs. It runs on its own fresh database with Supabase's
-- default privileges (tables and functions granted to anon/authenticated), like production.
create temp table attack_results (name text, outcome text);
grant all on attack_results to authenticated, anon;
create function pg_temp.result(p_name text, p_blocked boolean) returns void language sql as
  $$ insert into attack_results values (p_name, case when p_blocked then 'PASS' else 'VULNERABLE' end) $$;

insert into auth.users (id, email, raw_user_meta_data) values
 ('10000000-0000-0000-0000-00000000000a', 'artist1@x.io', '{"role":"artist"}'),
 ('10000000-0000-0000-0000-0000000000a2', 'artist2@x.io', '{"role":"artist"}'),
 ('10000000-0000-0000-0000-00000000000b', 'owner1@x.io', '{"role":"studio_owner"}'),
 ('10000000-0000-0000-0000-0000000000b2', 'owner2@x.io', '{"role":"studio_owner"}'),
 ('10000000-0000-0000-0000-00000000000c', 'admin1@x.io', '{"role":"artist"}');
update profiles set role = 'admin' where email = 'admin1@x.io';
update profiles set email_verified_at = now();

-- Owner 1 builds a studio that is open every day, accepts cash, instant book; admin approves it.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
insert into studios (id, owner_id, name, description, photo_urls, address, latitude, longitude, contact, session_types, add_ons, genres, opening_hours, booking_policy)
values ('20000000-0000-0000-0000-000000000001', auth.uid(), 'Attack Studio', repeat('x', 60), '{a.jpg}',
 '{"street":"S 1","postal_code":"1","city":"Athens","area":"Psyri","country":"GR"}', 37.9, 23.7,
 '{"phone":"+30 210 123 4567","email":"a@studio.gr","website":""}',
 '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":1,"includes_engineer":false}]',
 '[{"id":"mix","kind":"mixing","name":"Mixing","price":5000,"unit":"per_track"}]', '{pop}',
 (select jsonb_agg(jsonb_build_object('weekday', d, 'is_closed', false, 'opens_at', 0, 'closes_at', 1440)) from generate_series(1, 7) d),
 '{"instant_book":true,"accepts_cash":true,"deposit_percent":0}');
select submit_studio_for_review('20000000-0000-0000-0000-000000000001');
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select admin_review_studio('20000000-0000-0000-0000-000000000001', 'approve', null);
select 'attack studio', status, is_active from studios where id = '20000000-0000-0000-0000-000000000001';

-- Artist 1 makes a normal cash booking 3 days ahead.
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
create temp table artist_booking as
  select id from create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '3 days', 2, '[]', '');
grant all on artist_booking to authenticated, anon;
select confirm_cash_booking((select id from artist_booking));

----------------------------------------------------------------------------------------------------
-- Money
----------------------------------------------------------------------------------------------------

-- A studio owner sets a negative add-on price after approval, so bookings (and the 10% fee) go negative.
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000b';
do $$ begin
  update studios set add_ons = '[{"id":"neg","kind":"other","name":"Discount","price":-100000,"unit":"per_session"}]'
  where id = '20000000-0000-0000-0000-000000000001';
  perform pg_temp.result('negative add-on price rejected', false);
exception when others then perform pg_temp.result('negative add-on price rejected', true);
end $$;
do $$ begin
  update studios set session_types = '[{"id":"rec","name":"Recording","details":"","hourly_rate":0,"minimum_hours":1,"includes_engineer":false}]'
  where id = '20000000-0000-0000-0000-000000000001';
  perform pg_temp.result('zero hourly rate rejected', false);
exception when others then perform pg_temp.result('zero hourly rate rejected', true);
end $$;
do $$ begin
  update studios set booking_policy = booking_policy || '{"deposit_percent":-50}' where id = '20000000-0000-0000-0000-000000000001';
  perform pg_temp.result('negative deposit rejected', false);
exception when others then perform pg_temp.result('negative deposit rejected', true);
end $$;
-- Whatever was saved: a booking must never end up with a negative price or fee.
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a2';
do $$ declare b bookings; begin
  select * into b from create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '4 days', 1, '[{"id":"neg","quantity":1}]', '');
  perform pg_temp.result('booking price never negative', (b.price ->> 'total')::int >= 0 and (b.price ->> 'studio_commission')::int >= 0);
exception when others then perform pg_temp.result('booking price never negative', true);
end $$;
-- Restore a sane listing for the rest of the tests (as admin, so the guards don't interfere).
reset role;
update studios set add_ons = '[{"id":"mix","kind":"mixing","name":"Mixing","price":5000,"unit":"per_track"}]',
  session_types = '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":1,"includes_engineer":false}]',
  booking_policy = '{"instant_book":true,"accepts_cash":true,"deposit_percent":0}'
where id = '20000000-0000-0000-0000-000000000001';
delete from bookings where artist_id = '10000000-0000-0000-0000-0000000000a2';
set role authenticated;

-- An artist asks for a negative quantity of a paid add-on to lower the price.
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a2';
do $$ declare b bookings; begin
  select * into b from create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '5 days', 1, '[{"id":"mix","quantity":-5}]', '');
  perform pg_temp.result('negative add-on quantity ignored', (b.price ->> 'total')::int = 2500);
exception when others then perform pg_temp.result('negative add-on quantity ignored', true);
end $$;

-- An artist writes a booking row directly, picking their own price and status.
do $$ begin
  insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price, status, payment_status)
  values ('ES-HACK', auth.uid(), '20000000-0000-0000-0000-000000000001', 'x', 'x', 'rec', 'Recording', now() + interval '6 days', now() + interval '6 days 1 hour', 1, '{"total":1}', 'confirmed', 'paid');
  perform pg_temp.result('direct booking insert denied', false);
exception when others then perform pg_temp.result('direct booking insert denied', true);
end $$;

-- The artist marks their own (unpaid) booking as paid/confirmed.
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
update bookings set payment_status = 'paid', status = 'completed' where id = (select id from artist_booking);
select pg_temp.result('artist cannot mark booking paid',
  (select payment_status <> 'paid' from bookings where id = (select id from artist_booking)));

-- The artist confirms that the studio received the cash.
do $$ begin
  perform mark_cash_received((select id from artist_booking));
  perform pg_temp.result('artist cannot confirm cash received', false);
exception when others then perform pg_temp.result('artist cannot confirm cash received', true);
end $$;

-- Another artist cancels, reschedules or reads someone else's booking.
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a2';
select pg_temp.result('other artist cannot read booking', (select count(*) = 0 from bookings where id = (select id from artist_booking)));
do $$ begin
  perform cancel_booking((select id from artist_booking), 'gotcha');
  perform pg_temp.result('other artist cannot cancel booking', false);
exception when others then perform pg_temp.result('other artist cannot cancel booking', true);
end $$;
do $$ begin
  perform reschedule_booking((select id from artist_booking), date_trunc('hour', now()) + interval '8 days');
  perform pg_temp.result('other artist cannot reschedule booking', false);
exception when others then perform pg_temp.result('other artist cannot reschedule booking', true);
end $$;
do $$ begin
  perform check_in_booking((select id from artist_booking), 37.9, 23.7);
  perform pg_temp.result('other artist cannot check in', false);
exception when others then perform pg_temp.result('other artist cannot check in', true);
end $$;

-- Another studio owner accepts/declines, confirms arrival or rates the artist on a booking that isn't theirs.
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000b2';
do $$ begin
  perform respond_booking((select id from artist_booking), false, 'no');
  perform pg_temp.result('other owner cannot respond to booking', false);
exception when others then perform pg_temp.result('other owner cannot respond to booking', true);
end $$;
do $$ begin
  perform confirm_artist_arrival((select id from artist_booking));
  perform pg_temp.result('other owner cannot confirm arrival', false);
exception when others then perform pg_temp.result('other owner cannot confirm arrival', true);
end $$;
do $$ begin
  perform review_artist((select id from artist_booking), 1, 'bad');
  perform pg_temp.result('other owner cannot rate artist', false);
exception when others then perform pg_temp.result('other owner cannot rate artist', true);
end $$;
select pg_temp.result('other owner cannot read transactions', (select count(*) = 0 from transactions));
select pg_temp.result('other owner cannot read payout accounts', (select count(*) = 0 from studio_payout_accounts));

----------------------------------------------------------------------------------------------------
-- Accounts and privileges
----------------------------------------------------------------------------------------------------
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
do $$ begin
  perform claim_role('admin');
  perform pg_temp.result('cannot claim admin role', false);
exception when others then perform pg_temp.result('cannot claim admin role', true);
end $$;
update profiles set status = 'active', status_until = null, is_verified = true, role = 'admin' where id = auth.uid();
select pg_temp.result('cannot verify or promote self', (select not is_verified and role = 'artist' from profiles where id = auth.uid()));
update artist_profiles set is_verified = true, has_admin_badge = true, rating_average = 5, review_count = 999 where id = auth.uid();
select pg_temp.result('cannot fake artist badges or rating',
  (select not is_verified and not has_admin_badge and review_count = 0 from artist_profiles where id = auth.uid()));
select pg_temp.result('cannot read other profiles (emails)', (select count(*) = 1 from profiles));

-- Admin RPCs without admin, or as an admin without two-factor.
do $$ begin
  perform admin_set_platform_fee('20000000-0000-0000-0000-000000000001', 0);
  perform pg_temp.result('artist cannot call admin functions', false);
exception when others then perform pg_temp.result('artist cannot call admin functions', true);
end $$;
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal1"}';
do $$ begin
  perform admin_verify_user('10000000-0000-0000-0000-00000000000a', true);
  perform pg_temp.result('admin without 2FA denied', false);
exception when others then perform pg_temp.result('admin without 2FA denied', true);
end $$;
select pg_temp.result('admin without 2FA cannot read all profiles', (select count(*) = 1 from profiles));
set request.jwt.claims = '{}';

-- Studio owner tricks: fee, badges, approval, going live while suspended, a second studio.
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000b';
update studios set platform_fee_percent = 0, has_admin_badge = true, admin_tags = '{Staff pick}', promoted_until = now() + interval '1 year',
  is_verified = true, rating_average = 5, review_count = 500 where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.result('owner cannot change fee, badges, promotion or rating',
  (select platform_fee_percent = 10 and not has_admin_badge and admin_tags = '{}' and promoted_until is null and review_count = 0
   from studios where id = '20000000-0000-0000-0000-000000000001'));
update studios set owner_id = '10000000-0000-0000-0000-0000000000b2' where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.result('owner cannot give studio away', (select owner_id = '10000000-0000-0000-0000-00000000000b' from studios where id = '20000000-0000-0000-0000-000000000001'));

-- Owner 2 edits owner 1's studio or writes blocked time into it.
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000b2';
update studios set name = 'Hijacked' where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.result('other owner cannot edit studio', (select name = 'Attack Studio' from studios where id = '20000000-0000-0000-0000-000000000001'));
do $$ begin
  insert into blocked_slots (studio_id, starts_at, ends_at) values ('20000000-0000-0000-0000-000000000001', now() + interval '1 day', now() + interval '30 days');
  perform pg_temp.result('other owner cannot block time', false);
exception when others then perform pg_temp.result('other owner cannot block time', true);
end $$;

----------------------------------------------------------------------------------------------------
-- Messages, notifications, reviews, reports
----------------------------------------------------------------------------------------------------
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
create temp table artist_conv as select (get_or_create_conversation('20000000-0000-0000-0000-000000000001', null)).id as id;
grant all on artist_conv to authenticated, anon;

set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a2';
select pg_temp.result('outsider cannot read conversation', (select count(*) = 0 from conversations where id = (select id from artist_conv)));
do $$ begin
  insert into messages (conversation_id, sender_id, body) values ((select id from artist_conv), auth.uid(), 'spam');
  perform pg_temp.result('outsider cannot post in conversation', false);
exception when others then perform pg_temp.result('outsider cannot post in conversation', true);
end $$;

set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
do $$ begin
  insert into messages (conversation_id, sender_id, body) values ((select id from artist_conv), '10000000-0000-0000-0000-00000000000b', 'pay me outside the app');
  perform pg_temp.result('cannot send as someone else', false);
exception when others then perform pg_temp.result('cannot send as someone else', true);
end $$;
do $$ begin
  insert into messages (conversation_id, sender_id, body, kind) values ((select id from artist_conv), auth.uid(), 'Booking confirmed', 'system');
  perform pg_temp.result('cannot fake system messages', false);
exception when others then perform pg_temp.result('cannot fake system messages', true);
end $$;
do $$ begin
  insert into notifications (user_id, kind, title, body) values ('10000000-0000-0000-0000-0000000000a2', 'system', 'Warning from EasySesh', 'Send your password to…');
  perform pg_temp.result('cannot send notifications to others', false);
exception when others then perform pg_temp.result('cannot send notifications to others', true);
end $$;
do $$ begin
  insert into reviews (booking_id, studio_id, artist_id, artist_name, rating, facilities_rating, experience_rating, text)
  values ((select id from artist_booking), '20000000-0000-0000-0000-000000000001', auth.uid(), 'x', 1, 1, 1, 'never went');
  perform pg_temp.result('cannot review before the session', false);
exception when others then perform pg_temp.result('cannot review before the session', true);
end $$;
do $$ begin
  insert into reports (reporter_id, target_type, target_id, reason) values ('10000000-0000-0000-0000-0000000000a2', 'studio', '20000000-0000-0000-0000-000000000001', 'framed');
  perform pg_temp.result('cannot file reports as someone else', false);
exception when others then perform pg_temp.result('cannot file reports as someone else', true);
end $$;
do $$ begin
  insert into device_tokens (token, user_id) values ('stolen-token', '10000000-0000-0000-0000-0000000000a2');
  perform pg_temp.result('cannot register push token for someone else', false);
exception when others then perform pg_temp.result('cannot register push token for someone else', true);
end $$;
set request.jwt.claim.sub = '10000000-0000-0000-0000-00000000000a';
do $$ begin
  insert into device_tokens (token, user_id, platform) values ('../../3/device/abc?x=', auth.uid(), 'ios');
  perform pg_temp.result('malformed push token rejected', false);
exception when others then perform pg_temp.result('malformed push token rejected', true);
end $$;
do $$ begin
  insert into storage.objects (bucket_id, name) values ('media', '10000000-0000-0000-0000-0000000000a2/avatar/x.jpg');
  perform pg_temp.result('cannot upload into someone else''s folder', false);
exception when others then perform pg_temp.result('cannot upload into someone else''s folder', true);
end $$;

----------------------------------------------------------------------------------------------------
-- Internal functions that only the scheduler / server should run
----------------------------------------------------------------------------------------------------
do $$ declare f text; ok boolean := true; begin
  foreach f in array array['run_booking_housekeeping()', 'run_cash_housekeeping()', 'queue_session_reminders()', 'refresh_studio_rating(uuid)',
                           'refresh_artist_rating(uuid)', 'notify(uuid,notification_kind,text,text,uuid,uuid,uuid)', 'run_fee_enforcement()', 'create_fee_invoices()',
                           'lift_expired_moderation()', 'expire_promotions()', 'is_blocked_between(uuid,uuid)', 'activate_promotion(uuid)', 'resend_api_key()',
                           'issue_email_verification(uuid)', 'require_verified_email(uuid)']
  loop
    begin
      if has_function_privilege('authenticated', f::regprocedure, 'execute') or has_function_privilege('anon', f::regprocedure, 'execute') then
        raise notice 'callable by users: %', f; ok := false;
      end if;
    exception when undefined_function then null;
    end;
  end loop;
  perform pg_temp.result('internal jobs not callable by users', ok);
end $$;

----------------------------------------------------------------------------------------------------
-- Unverified email: can look around, can't book, message, review or verify themselves
----------------------------------------------------------------------------------------------------
reset role;
create temp table verify_token (token text);
grant all on verify_token to authenticated, anon;
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
 ('10000000-0000-0000-0000-0000000000a3', 'fresh@x.io', '{"role":"artist"}', '{"provider":"email"}'),
 ('10000000-0000-0000-0000-0000000000a4', 'apple@x.io', '{"role":"artist"}', '{"provider":"apple"}'),
 ('10000000-0000-0000-0000-0000000000b3', 'freshowner@x.io', '{"role":"studio_owner"}', '{"provider":"email"}');
select pg_temp.result('email sign-up starts unverified', (select email_verified_at is null from profiles where email = 'fresh@x.io'));
select pg_temp.result('apple sign-up counts as verified', (select email_verified_at is not null from profiles where email = 'apple@x.io'));
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a3';
set request.jwt.claims = '{}';
select pg_temp.result('unverified user can browse studios', (select count(*) > 0 from studios where status = 'approved'));
do $$ begin
  perform create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '11 days', 1, '[]', '');
  perform pg_temp.result('unverified user cannot book', false);
exception when others then perform pg_temp.result('unverified user cannot book', sqlerrm like 'Please verify your email%');
end $$;
do $$ begin
  perform get_or_create_conversation('20000000-0000-0000-0000-000000000001');
  perform pg_temp.result('unverified user cannot start a chat', false);
exception when others then perform pg_temp.result('unverified user cannot start a chat', sqlerrm like 'Please verify your email%');
end $$;
update profiles set email_verified_at = now() where id = auth.uid();
select pg_temp.result('cannot mark own email verified', (select email_verified_at is null from profiles where id = auth.uid()));
select pg_temp.result('made-up verification link rejected', not verify_email(repeat('a', 64)));
select pg_temp.result('cannot read verification tokens', not has_table_privilege('authenticated', 'email_verification_tokens', 'select'));
do $$ begin
  perform resend_email_verification();
  perform pg_temp.result('can ask for a new link', true);
exception when others then perform pg_temp.result('can ask for a new link', false);
end $$;
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000b3';
do $$ begin
  insert into studios (id, owner_id, name, description, photo_urls, address, latitude, longitude, contact, session_types, add_ons, genres, opening_hours, booking_policy)
  values ('20000000-0000-0000-0000-000000000009', auth.uid(), 'Fresh Studio', repeat('x', 60), '{a.jpg}',
   '{"street":"S 1","postal_code":"1","city":"Athens","area":"Psyri","country":"GR"}', 37.9, 23.7,
   '{"phone":"+30 210 123 4567","email":"a@studio.gr","website":""}',
   '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":1,"includes_engineer":false}]',
   '[]', '{pop}', (select jsonb_agg(jsonb_build_object('weekday', d, 'is_closed', false, 'opens_at', 0, 'closes_at', 1440)) from generate_series(1, 7) d), '{}');
  perform submit_studio_for_review('20000000-0000-0000-0000-000000000009');
  perform pg_temp.result('unverified studio cannot apply for approval', (select status <> 'pending_review' from studios where id = '20000000-0000-0000-0000-000000000009'));
exception when others then perform pg_temp.result('unverified studio cannot apply for approval', sqlerrm like 'Please verify your email%');
end $$;
reset role;
insert into verify_token select issue_email_verification('10000000-0000-0000-0000-0000000000a3') ->> 'token';
select pg_temp.result('second link within a minute not issued', issue_email_verification('10000000-0000-0000-0000-0000000000a3') is null);
set role anon;
set request.jwt.claim.sub = '';
select pg_temp.result('emailed link verifies', verify_email((select token from verify_token)));
select pg_temp.result('link works only once', not verify_email((select token from verify_token)));
reset role;
select pg_temp.result('verified after link', (select email_verified_at is not null from profiles where email = 'fresh@x.io'));
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-0000000000a3';
do $$ begin
  perform create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '11 days', 1, '[]', '');
  perform pg_temp.result('verified user can book', true);
exception when others then raise notice 'verified booking: %', sqlerrm; perform pg_temp.result('verified user can book', false);
end $$;
reset role;

-- Guests (signed out)
set role anon;
set request.jwt.claim.sub = '';
select pg_temp.result('guest cannot read profiles', (select count(*) = 0 from profiles));
select pg_temp.result('guest cannot read messages', (select count(*) = 0 from messages));
select pg_temp.result('guest cannot read bookings', (select count(*) = 0 from bookings));
do $$ begin
  perform create_booking('20000000-0000-0000-0000-000000000001', 'rec', date_trunc('hour', now()) + interval '9 days', 1, '[]', '');
  perform pg_temp.result('guest cannot book', false);
exception when others then perform pg_temp.result('guest cannot book', true);
end $$;
reset role;

select name, outcome from attack_results order by outcome desc, name;
