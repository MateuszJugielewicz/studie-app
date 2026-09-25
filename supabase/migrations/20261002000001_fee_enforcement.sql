-- EasySesh: collecting platform fees studios owe for cash bookings.
--  1. Fees are deducted from the studio's next card payout (process-payouts, unchanged).
--  2. Whatever is still owed on the 1st of the month is invoiced, due in 14 days.
--  3. Overdue: reminder at the due date, final notice after 7 days.
--  4. 14 days after the due date the studio is suspended (removed from EasySesh) and the invoice
--     goes to debt collection / legal action. Admins can record payment and reinstate the studio.

alter table public.studio_fee_invoices
  add column if not exists due_at timestamptz,
  add column if not exists reminder_sent_at timestamptz,
  add column if not exists final_notice_at timestamptz,
  add column if not exists collections_at timestamptz;
update public.studio_fee_invoices set due_at = created_at + interval '14 days' where due_at is null;
alter table public.studio_fee_invoices alter column due_at set default now() + interval '14 days';

alter table public.studio_fee_invoices drop constraint if exists studio_fee_invoices_status_check;
alter table public.studio_fee_invoices add constraint studio_fee_invoices_status_check
  check (status in ('open', 'paid', 'void', 'collections'));

-- Invoices whatever is still owed after payouts. Runs monthly; safe to run again.
create or replace function public.create_fee_invoices()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select l.studio_id, l.currency, sum(l.amount)::int as balance,
      coalesce((select sum(i.amount) from public.studio_fee_invoices i
                where i.studio_id = l.studio_id and i.currency = l.currency and i.status in ('open', 'collections')), 0)::int as invoiced
    from public.studio_fee_ledger l
    group by l.studio_id, l.currency
  loop
    continue when v_row.balance - v_row.invoiced <= 0;
    insert into public.studio_fee_invoices (studio_id, amount, currency, due_at)
    values (v_row.studio_id, v_row.balance - v_row.invoiced, v_row.currency, now() + interval '14 days');
    perform public.notify((select s.owner_id from public.studios s where s.id = v_row.studio_id), 'system',
      'Invoice for platform fees',
      'You owe ' || public.format_money(v_row.balance - v_row.invoiced, v_row.currency) ||
      ' in platform fees for cash bookings that could not be deducted from payouts. Please pay within 14 days (' ||
      to_char(now() + interval '14 days', 'DD Mon YYYY') || ').', null, null, v_row.studio_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function public.create_fee_invoices from public, anon, authenticated;

-- Reminders, final notice, suspension and debt collection. Runs daily.
create or replace function public.run_fee_enforcement()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_invoice record;
  v_owner uuid;
begin
  for v_invoice in select i.* from public.studio_fee_invoices i where i.status = 'open' and i.due_at < now() loop
    v_owner := (select s.owner_id from public.studios s where s.id = v_invoice.studio_id);

    if v_invoice.due_at < now() - interval '14 days' then
      update public.studio_fee_invoices set status = 'collections', collections_at = now() where id = v_invoice.id;
      update public.studios set status = 'suspended', is_active = false,
        admin_note = 'Suspended for unpaid platform fees (' || public.format_money(v_invoice.amount, v_invoice.currency) ||
                     '). The debt has been handed over for collection.'
      where id = v_invoice.studio_id and status <> 'suspended';
      perform public.notify(v_owner, 'system', 'Studio suspended – unpaid platform fees',
        'Your invoice of ' || public.format_money(v_invoice.amount, v_invoice.currency) ||
        ' is more than 14 days overdue. Your studio has been removed from EasySesh and the debt has been handed over for collection and legal action. Contact support to settle it.',
        null, null, v_invoice.studio_id);
    elsif v_invoice.due_at < now() - interval '7 days' and v_invoice.final_notice_at is null then
      update public.studio_fee_invoices set final_notice_at = now() where id = v_invoice.id;
      perform public.notify(v_owner, 'system', 'Final notice: unpaid platform fees',
        'Your invoice of ' || public.format_money(v_invoice.amount, v_invoice.currency) ||
        ' is overdue. Pay within 7 days, otherwise your studio will be removed from EasySesh and the debt handed over for collection and legal action.',
        null, null, v_invoice.studio_id);
    elsif v_invoice.reminder_sent_at is null then
      update public.studio_fee_invoices set reminder_sent_at = now() where id = v_invoice.id;
      perform public.notify(v_owner, 'system', 'Reminder: platform fee invoice due',
        'Your invoice of ' || public.format_money(v_invoice.amount, v_invoice.currency) || ' was due on ' ||
        to_char(v_invoice.due_at, 'DD Mon YYYY') || '. Please pay it as soon as possible.', null, null, v_invoice.studio_id);
    end if;
  end loop;
end;
$$;
revoke execute on function public.run_fee_enforcement from public, anon, authenticated;

-- When payments bring the balance to zero, open invoices are marked paid.
create or replace function public.settle_fee_invoices()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.amount < 0 and (select coalesce(sum(l.amount), 0) from public.studio_fee_ledger l
                          where l.studio_id = new.studio_id and l.currency = new.currency) <= 0 then
    update public.studio_fee_invoices set status = 'paid', paid_at = now()
    where studio_id = new.studio_id and currency = new.currency and status in ('open', 'collections');
  end if;
  return new;
end;
$$;
drop trigger if exists settle_fee_invoices on public.studio_fee_ledger;
create trigger settle_fee_invoices after insert on public.studio_fee_ledger
  for each row execute function public.settle_fee_invoices();

-- Admin: reinstate a studio that was suspended for unpaid fees once the debt is settled.
create or replace function public.admin_reinstate_studio(p_studio_id uuid)
returns public.studios
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_admin();
  if (select coalesce(sum(l.amount), 0) from public.studio_fee_ledger l where l.studio_id = p_studio_id) > 0 then
    raise exception 'This studio still owes platform fees. Record the payment first.';
  end if;
  update public.studios set status = 'approved', is_active = true, admin_note = null where id = p_studio_id;
  return (select s from public.studios s where s.id = p_studio_id);
end;
$$;

select cron.schedule('easysesh-fee-invoices', '10 6 1 * *', $$select public.create_fee_invoices()$$);
select cron.schedule('easysesh-fee-enforcement', '20 6 * * *', $$select public.run_fee_enforcement()$$);
