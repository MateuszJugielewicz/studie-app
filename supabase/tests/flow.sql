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
insert into studios (owner_id, name, description, photo_urls, address, latitude, longitude, contact, session_types, genres, opening_hours, status, is_verified, rating_average)
values ('00000000-0000-0000-0000-00000000000b', 'Test Studio', repeat('x', 50), '{a.jpg}', '{"street":"S 1","postal_code":"1","city":"Athens","area":"Psyri","country":"GR"}', 37.9, 23.7,
 '{"phone":"1","email":"a@b.c","website":""}', '[{"id":"rec","name":"Recording","details":"","hourly_rate":2500,"minimum_hours":2,"includes_engineer":false}]', '{pop}',
 '[{"weekday":2,"is_closed":false,"opens_at":600,"closes_at":1320}]', 'approved', true, 5);
select name, status, is_verified, rating_average, price_from from studios;
-- owner tries to self-approve via update
update studios set status='approved', is_active=true;
select 'after self-approve', status, is_active from studios;
select (submit_studio_for_review(id)).status from studios;

-- artist cannot see pending studio
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select 'artist sees', count(*) from studios;
update profiles set role='admin' where id = auth.uid();
select 'artist role after attempt', role from profiles;

-- admin approves
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select (admin_review_studio((select id from studios), 'approve', null)).status;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
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
select (get_or_create_conversation((select id from studios), (select id from bookings))).studio_name;
insert into messages (conversation_id, sender_id, body) values ((select id from conversations), auth.uid(), 'Hej!');
select 'busy', count(*) from studio_busy_intervals(array(select id from studios), now(), now() + interval '7 days');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
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
insert into reviews (booking_id, studio_id, artist_id, artist_name, rating, facilities_rating, experience_rating, text, studio_reply)
select id, studio_id, artist_id, 'x', 4, 5, 4, 'Great', 'fake reply' from bookings;
select 'review', artist_name, studio_reply from reviews;
select 'rating', rating_average, review_count from studios;
select 'has_review', has_review from bookings;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select (reply_to_review((select id from reviews), 'Thanks!')).studio_reply;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select 'stats' as label, (admin_dashboard_stats() ->> 'booking_rate')::numeric as rate, (admin_dashboard_stats() ->> 'studios_live')::int as live;
select count(*) from admin_users;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into storage.objects (bucket_id, name) values ('media', '00000000-0000-0000-0000-00000000000a/avatars/x.jpg');
select 'upload ok';
reset role;
select queue_session_reminders();
