grant usage on schema public, auth, storage to authenticated;
grant all on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema auth to authenticated;
grant all on storage.objects to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'artist@x.io', '{"role":"artist"}'),
 ('00000000-0000-0000-0000-00000000000b', 'owner@x.io', '{"role":"studio_owner"}'),
 ('00000000-0000-0000-0000-00000000000c', 'admin@x.io', '{"role":"admin"}');
update profiles set role='admin' where email='admin@x.io';
select email, role from profiles order by email;

-- owner creates studio as authenticated
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
insert into studios (owner_id, name, description, photo_urls, address, latitude, longitude, contact, session_types, genres, opening_hours, status, is_verified, rating_average)
values ('00000000-0000-0000-0000-00000000000b', 'Test Studio', repeat('x', 50), '{a.jpg}', '{"street":"S 1","postal_code":"1","city":"Athens","area":"Psyri","country":"GR"}', 37.9, 23.7,
 '{"phone":"+30 210 123 4567","email":"hello@studio.gr","website":""}', '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":2,"includes_engineer":false}]', '{pop}',
 '[{"weekday":2,"is_closed":false,"opens_at":600,"closes_at":1320}]', 'approved', true, 5);
select name, status, is_verified, rating_average, price_from from studios;
-- owner tries to self-approve via update
update studios set status='approved', is_active=true;
select 'after self-approve', status, is_active from studios;
-- editing the application again via upsert (what the app does) must work
insert into studios (id, owner_id, name) select id, owner_id, 'Renamed Studio' from studios
  on conflict (id) do update set name = excluded.name, status = excluded.status;
select 'resave', name, status from studios;
do $$ begin
  insert into studios (owner_id, name) values (auth.uid(), 'Second studio');
  create temp table second_studio as select 'NOT BLOCKED' r;
exception when others then create temp table second_studio as select 'second studio denied' r;
end $$;
select * from second_studio;
select (submit_studio_for_review(id)).status from studios;
do $$ begin
  insert into blocked_slots (studio_id, starts_at, ends_at) select id, now(), now() + interval '1 hour' from studios;
  create temp table unapproved_block as select 'NOT BLOCKED' r;
exception when others then create temp table unapproved_block as select 'unapproved block denied' r;
end $$;
select * from unapproved_block;

-- artist cannot see pending studio
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'artist sees', count(*) from studios;
do $$ begin
  insert into studios (owner_id, name) values (auth.uid(), 'Sneaky studio');
  create temp table artist_studio as select 'NOT BLOCKED' r;
exception when others then create temp table artist_studio as select 'artist studio denied' r;
end $$;
select * from artist_studio;
update profiles set role='admin' where id = auth.uid();
select 'artist role after attempt', role from profiles;

-- admin approves
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
set request.jwt.claims = '{"aal":"aal1"}';
do $$ begin
  perform admin_review_studio((select id from studios), 'approve', null);
  create temp table admin_mfa as select 'NOT BLOCKED' r;
exception when others then create temp table admin_mfa as select 'admin without mfa denied' r;
end $$;
select * from admin_mfa;
set request.jwt.claims = '{"aal":"aal2"}';
select (admin_review_studio((select id from studios), 'approve', null)).status;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'artist sees', count(*) from studios;
-- a listing save with a stale is_active=false must not pause an approved studio
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
insert into studios (id, owner_id, name, is_active) select id, owner_id, name, false from studios
  on conflict (id) do update set name = excluded.name, is_active = excluded.is_active;
select 'still live' as label, status, is_active from studios;
reset role;

-- service creates booking (edge function), overlap blocked
insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price)
select 'SON-1', '00000000-0000-0000-0000-00000000000a', id, 'Nova', name, 'rec', 'Recording', now() + interval '2 days', now() + interval '2 days 2 hours', 2, '{"currency":"EUR","subtotal":5000,"studio_commission":250,"service_fee":400}' from studios;
do $$ begin
  insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price)
  select 'SON-2', '00000000-0000-0000-0000-00000000000a', id, 'Nova', name, 'rec', 'Recording', now() + interval '2 days 1 hour', now() + interval '2 days 3 hours', 2, '{}' from studios;
  create temp table overlap_result as select 'NOT BLOCKED' r;
exception when exclusion_violation then create temp table overlap_result as select 'blocked ok' r;
end $$;
select * from overlap_result;
update bookings set status='confirmed', payment_status='paid' where reference='SON-1';
select 'booking_count', booking_count from studios;

-- chat
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select (get_or_create_conversation((select id from studios), (select id from bookings))).studio_name;
insert into messages (conversation_id, sender_id, body) values ((select id from conversations), auth.uid(), 'Hej!');
select 'busy', count(*) from studio_busy_intervals(array(select id from studios), now(), now() + interval '7 days');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select 'owner unread', studio_unread, last_message_preview from conversations;
select mark_conversation_read((select id from conversations));
update notifications set title='hacked';
select 'notif title', title, is_read from notifications limit 1;
reset role;

-- complete + review
update bookings set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour', status='confirmed';
select run_booking_housekeeping();
select 'status', status from bookings;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
insert into reviews (booking_id, studio_id, artist_id, artist_name, rating, facilities_rating, experience_rating, text, studio_reply)
select id, studio_id, artist_id, 'x', 4, 5, 4, 'Great', 'fake reply' from bookings;
select 'review', artist_name, studio_reply from reviews;
select 'rating', rating_average, review_count from studios;
select 'has_review', has_review from bookings;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select (reply_to_review((select id from reviews), 'Thanks!')).studio_reply;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'stats' as label, (admin_dashboard_stats() ->> 'booking_rate')::numeric as rate, (admin_dashboard_stats() ->> 'studios_live')::int as live;
select count(*) from admin_users;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
insert into storage.objects (bucket_id, name) values ('media', '00000000-0000-0000-0000-00000000000a/avatars/x.jpg');
select 'upload ok';
reset role;
select queue_session_reminders();

-- cash booking: completion accrues 10% fee owed by the studio
insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price, status, payment_method, payment_status)
select 'SON-CASH', '00000000-0000-0000-0000-00000000000a', id, 'Nova', name, 'rec', 'Recording', now() - interval '5 hours', now() - interval '3 hours', 2,
  '{"currency":"EUR","subtotal":5000,"total":5000,"studio_commission":500,"service_fee":0,"studio_payout":4500}', 'confirmed', 'cash', 'pay_at_studio' from studios;
select run_booking_housekeeping();
select 'fee balance' as label, balance from studio_fee_balances;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select 'cash received' as label, (mark_cash_received((select id from bookings where reference = 'SON-CASH'))).payment_status as status;
select 'owner sees ledger' as label, count(*) as n from studio_fee_ledger;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'settled' as label, (admin_record_fee_settlement((select id from studios), 500, 'EUR', 'manual_payment', 'bank transfer')).amount as amount;
select 'balance after' as label, balance from studio_fee_balances;
select 'terms' as label, (accept_terms('2026-09-25')).accepted_terms_version as version;
reset role;

-- support: artist opens a ticket, admin answers, other users can't see or post
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'ticket created' as label, (create_support_ticket('Refund question', 'payment', 'Where is my refund?', null)).status as status;
do $$ begin
  insert into support_messages (ticket_id, body, from_admin) select id, 'fake admin', true from support_tickets;
  create temp table support_forge as select 'NOT BLOCKED' r;
exception when others then create temp table support_forge as select 'support forge denied' r;
end $$;
select * from support_forge;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select 'owner sees tickets' as label, count(*) as n from support_tickets;
do $$ begin
  perform send_support_message((select id from admin_support_tickets limit 1), 'hi');
  create temp table support_other as select 'NOT BLOCKED' r;
exception when others then create temp table support_other as select 'support other denied' r;
end $$;
select * from support_other;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'admin inbox' as label, user_name, admin_unread from admin_support_tickets;
select (send_support_message((select id from support_tickets), 'Refund sent today.')).from_admin;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'ticket answered' as label, status, user_unread, (select count(*) from support_messages) as n from support_tickets;
select 'support notified' as label, count(*) as n from notifications where title = 'EasySesh support replied';
select 'ticket closed' as label, (set_support_ticket_status((select id from support_tickets), 'closed')).status as status;
reset role;

-- message requests: studio writes to a new artist → request; artist declines → studio blocked
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-00000000000d', 'new@x.io', '{"role":"artist"}');
update artist_profiles set artist_name = 'Luna Beats' where id = '00000000-0000-0000-0000-00000000000d';
update artist_profiles set artist_name = 'Nova' where id = '00000000-0000-0000-0000-00000000000a';
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select 'artist search' as label, count(*) as n from search_artists('luna');
select 'known artist' as label, (studio_start_conversation('00000000-0000-0000-0000-00000000000a', 'Hi again!')).request_status as status;
select 'cold request' as label, (studio_start_conversation('00000000-0000-0000-0000-00000000000d', 'Want to record with us?')).request_status as status;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select 'request notified' as label, count(*) as n from notifications where title like 'Message request%';
select 'declined' as label, (respond_message_request((select id from conversations where artist_id = auth.uid()), false)).request_status as status;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  perform studio_start_conversation('00000000-0000-0000-0000-00000000000d', 'Hello??');
  create temp table declined_block as select 'NOT BLOCKED' r;
exception when others then create temp table declined_block as select 'declined request blocks studio' r;
end $$;
select * from declined_block;
do $$ begin
  insert into messages (conversation_id, sender_id, kind, body)
  select id, auth.uid(), 'text', 'sneaky' from conversations where artist_id = '00000000-0000-0000-0000-00000000000d';
  create temp table declined_insert as select 'NOT BLOCKED' r;
exception when others then create temp table declined_insert as select 'declined direct insert blocked' r;
end $$;
select * from declined_insert;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  perform search_artists('luna');
  create temp table artist_search as select 'NOT BLOCKED' r;
exception when others then create temp table artist_search as select 'artist cannot search artists' r;
end $$;
select * from artist_search;
reset role;

-- support ratings: only the owner, only when closed
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'support rated' as label, (rate_support_ticket((select id from support_tickets limit 1), 5, 'Quick and friendly')).rating as rating;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  perform rate_support_ticket((select id from admin_support_tickets limit 1), 1, 'not mine');
  create temp table rate_other as select 'NOT BLOCKED' r;
exception when others then create temp table rate_other as select 'rating others denied' r;
end $$;
select * from rate_other;
reset role;

-- badges, admin tags, promotions: only admins, owners/artists can't set them themselves
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
update artist_profiles set has_admin_badge = true where id = auth.uid();
select 'self badge' as label, has_admin_badge from artist_profiles where id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
update studios set admin_tags = '{Hacked}', promoted_until = now() + interval '1 year', has_admin_badge = true;
select 'self promo' as label, admin_tags, promoted_until, has_admin_badge from studios;
do $$ begin
  perform admin_grant_promotion((select id from studios), 7, 'nope');
  create temp table owner_grant as select 'NOT BLOCKED' r;
exception when others then create temp table owner_grant as select 'owner grant denied' r;
end $$;
select * from owner_grant;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select admin_set_admin_badge('00000000-0000-0000-0000-00000000000a', true);
select 'admin tags' as label, array_length((admin_set_studio_tags((select id from studios), array['Staff pick', ' ', 'Staff pick', 'Top engineer'])).admin_tags, 1) as n;
select 'granted' as label, (admin_grant_promotion((select id from studios), 7, 'launch')).status as status;
select 'promoted' as label, (promoted_until > now() + interval '6 days') as ok from studios;
select 'badge set' as label, has_admin_badge from artist_profiles where id = '00000000-0000-0000-0000-00000000000a';
reset role;

-- bookings in the database (no edge functions / Stripe needed)
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
create temp table db_booking as
  select * from create_booking((select id from studios), 'rec', date_trunc('week', now()) + interval '7 days 12 hours', 2, '[]', 'first session');
select 'db booking' as label, status, (price ->> 'subtotal')::int as subtotal, reference like 'ES-%' as ref_ok from db_booking;
do $$ begin
  perform create_booking((select id from studios), 'rec', date_trunc('week', now()) + interval '7 days 12 hours', 2, '[]', '');
  create temp table db_clash as select 'NOT BLOCKED' r;
exception when others then create temp table db_clash as select 'db clash blocked' r;
end $$;
select * from db_clash;
do $$ begin
  perform create_booking((select id from studios), 'rec', date_trunc('week', now()) + interval '7 days 21 hours', 2, '[]', '');
  create temp table db_hours as select 'NOT BLOCKED' r;
exception when others then create temp table db_hours as select 'db closed hours blocked' r;
end $$;
select * from db_hours;
select 'db cash' as label, (confirm_cash_booking((select id from db_booking))).status as status;
select 'db moved' as label, extract(hour from (reschedule_booking((select id from db_booking), date_trunc('week', now()) + interval '7 days 15 hours')).starts_at at time zone 'UTC')::int as hour;
select 'db cancelled' as label, (cancel_booking((select id from db_booking), 'changed plans')).status as status;
reset role;

-- studios rate artists; notifications can be deleted
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select 'artist rated' as label, (review_artist((select id from bookings where reference = 'SON-CASH'), 4, 'Great energy')).rating as rating;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select 'artist rating' as label, rating_average::float as avg, review_count from artist_profiles where id = auth.uid();
update artist_profiles set rating_average = 5, review_count = 99 where id = auth.uid();
select 'rating locked' as label, review_count from artist_profiles where id = auth.uid();
do $$ begin
  perform review_artist((select id from bookings where reference = 'SON-CASH'), 5, 'self');
  create temp table self_review as select 'NOT BLOCKED' r;
exception when others then create temp table self_review as select 'artist self review denied' r;
end $$;
select * from self_review;
delete from notifications where user_id = auth.uid();
select 'notifications deleted' as label, count(*) as n from notifications where user_id = auth.uid();
reset role;

-- promotion requests: studio orders, admin activates
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
create temp table promo_request as select * from request_promotion('two_weeks');
select 'promo requested' as label, status, days, amount, currency from promo_request;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'promo activated' as label, (admin_activate_promotion((select id from promo_request))).status as status;
select 'promo pending list' as label, count(*) as n from admin_promotions where status = 'pending';
reset role;

-- platform fee enforcement: invoice → reminder → final notice → suspension/collections
insert into studio_fee_ledger (studio_id, kind, amount, currency, note) select id, 'cash_commission', 700, 'EUR', 'test fee' from studios;
select 'fee invoices created' as label, create_fee_invoices() as n;
update studio_fee_invoices set due_at = now() - interval '1 day' where status = 'open';
select run_fee_enforcement();
select 'fee reminder' as label, count(*) as n from studio_fee_invoices where reminder_sent_at is not null;
update studio_fee_invoices set due_at = now() - interval '8 days' where status = 'open';
select run_fee_enforcement();
select 'fee final notice' as label, count(*) as n from studio_fee_invoices where final_notice_at is not null;
update studio_fee_invoices set due_at = now() - interval '15 days' where status = 'open';
select run_fee_enforcement();
select 'fee collections' as label, (select status from studio_fee_invoices order by created_at desc limit 1) as invoice_status,
  (select status::text from studios limit 1) as studio_status, (select is_active from studios limit 1) as active;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select admin_record_fee_settlement((select id from studios), 700, 'EUR', 'manual_payment', 'bank transfer');
select 'fee reinstated' as label, (admin_reinstate_studio((select id from studios))).status::text as status,
  (select status from studio_fee_invoices order by created_at desc limit 1) as invoice_status;
reset role;

-- special deals (own platform fee), contact rules, rating disputes
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'fee deal' as label, (admin_set_platform_fee((select id from studios), 5)).platform_fee_percent as pct;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'deal booking' as label, (price ->> 'studio_commission')::int as commission, (price ->> 'subtotal')::int as subtotal
  from create_booking((select id from studios), 'rec', date_trunc('week', now()) + interval '14 days 12 hours', 2, '[]', '');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
update studios set platform_fee_percent = 0;
select 'deal locked' as label, platform_fee_percent from studios;
select 'contact rules' as label,
  'Add a phone number.' = any(studio_validation_problems(jsonb_populate_record(null::studios,
    to_jsonb(st) || '{"contact":{"phone":"","email":"hello@studio.gr","website":""}}'))) as needs_phone
  from studios st;
-- studio disputes the artist's review of it
create temp table rd as select * from dispute_rating('studio_review', (select id from reviews limit 1), 'This review is from someone who never came.');
select 'rating disputed' as label, status from rd;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
create temp table rd_done as select * from admin_resolve_rating_dispute((select id from rd), true, 'Fake review');
select 'dispute resolved' as label, (select status from rd_done) as status, (select is_hidden from reviews limit 1) as hidden;
reset role;

-- studio ↔ artist profile connection
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
set request.jwt.claims = '{}';
select 'link requested' as label, (request_studio_artist_link('00000000-0000-0000-0000-00000000000a')).status as status;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select 'link hidden while pending' as label, count(*) as n from studio_artist_links;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select respond_studio_artist_link((select studio_id from studio_artist_links limit 1), true);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select 'link public' as label, status from studio_artist_links;
reset role;

-- unanswered requests expire after 24 hours
insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price, status, payment_method, payment_status, created_at)
select 'ES-REQ', '00000000-0000-0000-0000-00000000000a', id, 'Nova', name, 'rec', 'Recording', now() + interval '20 days', now() + interval '20 days 2 hours', 2,
  '{"currency":"EUR","subtotal":5000,"total":5000,"studio_commission":500,"service_fee":0,"studio_payout":4500}', 'pending_approval', 'cash', 'pay_at_studio', now() - interval '25 hours' from studios;
select run_booking_housekeeping();
select 'request expired' as label, status, payment_status from bookings where reference = 'ES-REQ';

-- check-in on arrival
insert into bookings (reference, artist_id, studio_id, artist_name, studio_name, session_type_id, session_type_name, starts_at, ends_at, hours, price, status, payment_method, payment_status)
select 'ES-NOW', '00000000-0000-0000-0000-00000000000a', id, 'Nova', name, 'rec', 'Recording', now() + interval '20 minutes', now() + interval '2 hours 20 minutes', 2,
  '{"currency":"EUR","subtotal":5000,"total":5000,"studio_commission":500,"service_fee":0,"studio_payout":4500}', 'confirmed', 'cash', 'pay_at_studio' from studios;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'checked in' as label, (b).artist_checked_in_at is not null as ok, (b).artist_check_in_distance_m as dist
  from (select check_in_booking((select id from bookings where reference = 'ES-NOW'), 37.9001, 23.7001) as b) q;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select 'arrival confirmed' as label, (confirm_artist_arrival((select id from bookings where reference = 'ES-NOW'))).studio_confirmed_arrival_at is not null as ok;
reset role;

-- changelog + legal update forces everyone to accept again
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
create temp table cl as select * from admin_publish_changelog('2.0', 'Updated terms', 'New check-in rules.', 'all', true);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'changelog visible' as label, count(*) as n, current_terms_version() > '2026-09-25' as bumped from app_changelog;
do $$ begin
  perform accept_terms('2026-09-25');
  create temp table old_terms as select 'NOT BLOCKED' r;
exception when others then create temp table old_terms as select 'old terms refused' r;
end $$;
select * from old_terms;
select 'terms accepted' as label, (accept_terms(current_terms_version())).accepted_terms_version = current_terms_version() as ok;
reset role;

-- moderation: warning, timed suspension that lifts itself, history
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'warned' as label, (admin_warn('00000000-0000-0000-0000-00000000000a', 'Be respectful in messages.')).action as action;
select 'suspended 3 days' as label, (p).status, round(extract(epoch from (p).status_until - now()) / 86400) as days
  from (select admin_moderate_user('00000000-0000-0000-0000-00000000000a', 'suspend', 3, 'Spam') as p) q;
select 'studio suspended 1 day' as label, (s).status, (s).is_active
  from (select admin_moderate_studio((select id from studios limit 1), 'suspend', 1, 'Misleading photos') as s) q;
reset role;
update profiles set status_until = now() - interval '1 minute' where id = '00000000-0000-0000-0000-00000000000a';
update studios set suspended_until = now() - interval '1 minute';
select lift_expired_moderation();
select 'moderation lifted' as label, (select status from profiles where id = '00000000-0000-0000-0000-00000000000a') as user_status,
  (select status from studios limit 1) as studio_status;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
set request.jwt.claims = '{"aal":"aal2"}';
select 'moderation history' as label, count(*) filter (where kind = 'warning') as warnings, count(*) filter (where kind = 'suspension') as suspensions,
  count(*) filter (where kind = 'lifted') as lifted from admin_moderation_history where user_id = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.claims = '{}';
select 'own warnings' as label, count(*) as n from moderation_actions where action = 'warning' and acknowledged_at is null;
reset role;
