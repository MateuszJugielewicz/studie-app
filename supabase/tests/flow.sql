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
 '{"phone":"1","email":"a@b.c","website":""}', '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":2,"includes_engineer":false}]', '{pop}',
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
