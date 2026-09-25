-- EasySesh: "Download my data" (GDPR art. 15/20) straight from the database, so it works without
-- the export-data edge function being deployed. Returns everything stored about the caller.
create or replace function public.export_my_data()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := auth.uid();
  v_studios uuid[];
  v_bookings uuid[];
begin
  if v_id is null then raise exception 'not_authenticated'; end if;
  v_studios := array(select id from public.studios where owner_id = v_id);
  v_bookings := array(select id from public.bookings where artist_id = v_id or studio_id = any(v_studios));

  return jsonb_build_object(
    'exported_at', now(),
    'notice', 'This file contains the personal data EasySesh holds about you (GDPR art. 15 and 20). Card numbers are held by Stripe and never stored by EasySesh.',
    'account', (select to_jsonb(p) - 'stripe_customer_id' from public.profiles p where p.id = v_id),
    'artist_profile', (select to_jsonb(a) from public.artist_profiles a where a.id = v_id),
    'studios', coalesce((select jsonb_agg(to_jsonb(s)) from public.studios s where s.id = any(v_studios)), '[]'),
    'bookings_as_artist', coalesce((select jsonb_agg(to_jsonb(b) order by b.starts_at) from public.bookings b where b.artist_id = v_id), '[]'),
    'bookings_at_my_studio', coalesce((select jsonb_agg(to_jsonb(b) order by b.starts_at) from public.bookings b where b.studio_id = any(v_studios)), '[]'),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'booking_id', t.booking_id, 'kind', t.kind, 'method', t.method, 'status', t.status, 'amount', t.amount,
        'currency', t.currency, 'receipt_number', t.receipt_number, 'card_brand', t.card_brand, 'card_last4', t.card_last4,
        'created_at', t.created_at) order by t.created_at)
      from public.transactions t where t.booking_id = any(v_bookings)), '[]'),
    'payouts', coalesce((select jsonb_agg(to_jsonb(p) order by p.scheduled_for) from public.payouts p where p.studio_id = any(v_studios)), '[]'),
    'platform_fees', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at) from public.studio_fee_ledger f where f.studio_id = any(v_studios)), '[]'),
    'fee_invoices', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at) from public.studio_fee_invoices i where i.studio_id = any(v_studios)), '[]'),
    'conversations', coalesce((select jsonb_agg(to_jsonb(c)) from public.conversations c where c.artist_id = v_id or c.studio_id = any(v_studios)), '[]'),
    'messages_sent', coalesce((select jsonb_agg(jsonb_build_object('conversation_id', m.conversation_id, 'kind', m.kind, 'body', m.body, 'created_at', m.created_at) order by m.created_at)
      from public.messages m where m.sender_id = v_id), '[]'),
    'support_requests', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('messages',
        coalesce((select jsonb_agg(jsonb_build_object('from_admin', sm.from_admin, 'body', sm.body, 'created_at', sm.created_at) order by sm.created_at)
          from public.support_messages sm where sm.ticket_id = t.id), '[]')))
      from public.support_tickets t where t.user_id = v_id), '[]'),
    'reviews_written', coalesce((select jsonb_agg(to_jsonb(r)) from public.reviews r where r.artist_id = v_id), '[]'),
    'ratings_from_studios', coalesce((select jsonb_agg(to_jsonb(r)) from public.artist_reviews r where r.artist_id = v_id), '[]'),
    'ratings_given_to_artists', coalesce((select jsonb_agg(to_jsonb(r)) from public.artist_reviews r where r.studio_id = any(v_studios)), '[]'),
    'reports_made', coalesce((select jsonb_agg(to_jsonb(r)) from public.reports r where r.reporter_id = v_id), '[]'),
    'moderation', coalesce((select jsonb_agg(jsonb_build_object('action', m.action, 'reason', m.reason, 'ends_at', m.ends_at, 'created_at', m.created_at) order by m.created_at)
      from public.moderation_actions m where m.user_id = v_id), '[]'),
    'notifications', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at) from public.notifications n where n.user_id = v_id), '[]'),
    'devices', coalesce((select jsonb_agg(jsonb_build_object('platform', d.platform, 'created_at', d.created_at)) from public.device_tokens d where d.user_id = v_id), '[]')
  );
end;
$$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
