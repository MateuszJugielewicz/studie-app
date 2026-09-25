-- EasySesh: booking requests (studios without instant booking) must be answered within 24 hours,
-- otherwise they expire and the artist is told. Studios are paid only after a completed session
-- (process-payouts schedules payouts for completed bookings only, 2 days after the session ends).

create or replace function public.run_booking_housekeeping()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_expired record;
begin
  -- Unpaid holds release the slot after 30 minutes.
  update public.bookings set status = 'expired'
  where status = 'awaiting_payment' and created_at < now() - interval '30 minutes';

  -- Requests the studio didn't answer within 24 hours (or before the session starts) expire.
  -- Card authorisations are released by the edge function; cash bookings had nothing charged.
  for v_expired in
    update public.bookings set status = 'expired',
      payment_status = case when payment_method = 'cash' then 'unpaid'::public.payment_status else 'refunded'::public.payment_status end
    where status = 'pending_approval' and (starts_at < now() or created_at < now() - interval '24 hours')
    returning id, artist_id, studio_name
  loop
    perform public.notify(v_expired.artist_id, 'booking_declined', 'Request expired',
      v_expired.studio_name || ' didn''t answer within 24 hours, so your request expired. Nothing was charged.', v_expired.id);
  end loop;

  -- Finished sessions complete (triggers review prompt; payouts/balance charges run in process-payouts).
  update public.bookings set status = 'completed'
  where status = 'confirmed' and ends_at < now();
end;
$$;
