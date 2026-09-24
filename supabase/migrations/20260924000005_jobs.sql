-- Sonora: scheduled jobs (pg_cron) and push delivery (pg_net → send-push edge function).
--
-- Setup (once per project), in the SQL editor:
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create or replace function public.call_edge_function(p_name text, p_body jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  base_url text := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url');
  key text := (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key');
begin
  if base_url is null or key is null then
    return; -- not configured (e.g. local dev without secrets)
  end if;
  perform net.http_post(
    url := base_url || '/functions/v1/' || p_name,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || key),
    body := p_body
  );
end;
$$;
revoke execute on function public.call_edge_function from public, anon, authenticated;

-- Every new notification is pushed to the user's devices (the function applies their settings).
create or replace function public.on_notification_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.call_edge_function('send-push', jsonb_build_object('notification_id', new.id));
  return new;
end;
$$;
create trigger on_notification_insert after insert on public.notifications
  for each row execute function public.on_notification_insert();

-- Time-based booking transitions.
create or replace function public.run_booking_housekeeping()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  -- Unpaid holds release the slot after 30 minutes.
  update public.bookings set status = 'expired'
  where status = 'awaiting_payment' and created_at < now() - interval '30 minutes';

  -- Requests the studio never answered expire at session start (authorisation is released by the edge function).
  update public.bookings set status = 'expired', payment_status = 'refunded'
  where status = 'pending_approval' and starts_at < now();

  -- Finished sessions complete (triggers review prompt; payouts/balance charges run in process-payouts).
  update public.bookings set status = 'completed'
  where status = 'confirmed' and ends_at < now();
end;
$$;

-- Session reminders 24h and 2h before start.
create or replace function public.queue_session_reminders()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  b record;
begin
  for b in
    select * from public.bookings
    where status = 'confirmed' and reminder_24h_sent_at is null
      and starts_at between now() + interval '23 hours' and now() + interval '24 hours 15 minutes'
  loop
    perform public.notify(b.artist_id, 'session_reminder', 'Session tomorrow',
      b.session_type_name || ' at ' || b.studio_name || ', ' || public.format_local(b.starts_at, b.studio_id) || '.', b.id);
    update public.bookings set reminder_24h_sent_at = now() where id = b.id;
  end loop;

  for b in
    select * from public.bookings
    where status = 'confirmed' and reminder_2h_sent_at is null
      and starts_at between now() + interval '1 hour 45 minutes' and now() + interval '2 hours 15 minutes'
  loop
    perform public.notify(b.artist_id, 'session_reminder', 'Session in 2 hours',
      b.session_type_name || ' at ' || b.studio_name || '. See you there!', b.id);
    update public.bookings set reminder_2h_sent_at = now() where id = b.id;
  end loop;
end;
$$;

select cron.schedule('sonora-booking-housekeeping', '*/10 * * * *', $$select public.run_booking_housekeeping()$$);
select cron.schedule('sonora-session-reminders', '*/15 * * * *', $$select public.queue_session_reminders()$$);
select cron.schedule('sonora-process-payouts', '7 * * * *', $$select public.call_edge_function('process-payouts')$$);
