-- "Delete studio" in the admin panel only took a studio offline when it had any bookings, so receipts stay
-- valid. Bookings without real money (cash, unpaid, cancelled, test bookings) don't need that: such a
-- studio is now removed completely, bookings included. A studio with a card payment, a payout or a paid
-- fee invoice is still only taken offline (those are accounting records). Called after admin-delete.
create or replace function public.admin_purge_studio(p_studio_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_bookings uuid[];
begin
  perform public.require_admin();
  if not public.has_admin_rank('admin') then raise exception 'Only admins can delete studios.' using errcode = '42501'; end if;
  if not exists (select 1 from public.studios s where s.id = p_studio_id) then return true; end if;
  if exists (select 1 from public.transactions t where t.studio_id = p_studio_id and t.status = 'succeeded')
     or exists (select 1 from public.payouts p where p.studio_id = p_studio_id)
     or exists (select 1 from public.studio_fee_invoices i where i.studio_id = p_studio_id and i.status = 'paid') then
    return false;
  end if;

  v_bookings := array(select b.id from public.bookings b where b.studio_id = p_studio_id);
  delete from public.studio_fee_ledger where studio_id = p_studio_id or booking_id = any (v_bookings);
  delete from public.transactions where studio_id = p_studio_id or booking_id = any (v_bookings);
  delete from public.reviews where studio_id = p_studio_id or booking_id = any (v_bookings);
  delete from public.disputes where booking_id = any (v_bookings);
  delete from public.bookings where id = any (v_bookings);
  delete from public.studios where id = p_studio_id;
  return true;
end;
$$;
revoke execute on function public.admin_purge_studio(uuid) from public, anon;
grant execute on function public.admin_purge_studio(uuid) to authenticated;
