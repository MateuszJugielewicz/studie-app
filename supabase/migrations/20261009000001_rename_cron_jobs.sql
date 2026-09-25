-- EasySesh: scheduled jobs were renamed from "sonora-*" to "easysesh-*". Schedule every job
-- under its new name (same schedule as before; scheduling a name again just updates it), then
-- remove the old names so nothing runs twice.
select cron.schedule('easysesh-booking-housekeeping', '*/10 * * * *', $$select public.run_booking_housekeeping()$$);
select cron.schedule('easysesh-session-reminders', '*/15 * * * *', $$select public.queue_session_reminders()$$);
select cron.schedule('easysesh-process-payouts', '7 * * * *', $$select public.call_edge_function('process-payouts')$$);
select cron.schedule('easysesh-cash-housekeeping', '17 * * * *', $$select public.run_cash_housekeeping()$$);

do $$
declare
  v_job text;
begin
  for v_job in select jobname from cron.job where jobname like 'sonora-%' loop
    perform cron.unschedule(v_job);
  end loop;
exception when others then
  raise notice 'Old scheduled jobs not removed: %', sqlerrm;
end $$;
