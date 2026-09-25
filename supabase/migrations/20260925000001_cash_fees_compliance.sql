-- EasySesh: cash payments, platform-fee ledger for studios, terms acceptance (GDPR) and approval gating.
--
-- Money model: EasySesh takes 10% of every sale (price ->> 'studio_commission').
--  * Card:  the artist pays EasySesh, EasySesh pays the studio 90% (payouts).
--  * Cash:  the artist pays the studio at the session; the studio owes EasySesh 10%.
--           Owed fees are netted against the studio's next card payouts, invoiced, or paid manually.

-- ---------------------------------------------------------------------------
-- Fee ledger: positive = studio owes EasySesh, negative = settled.
-- ---------------------------------------------------------------------------
create table public.studio_fee_ledger (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  booking_id uuid references public.bookings (id),
  payout_id uuid references public.payouts (id),
  invoice_id uuid,
  kind text not null check (kind in ('cash_commission', 'payout_offset', 'invoice_payment', 'manual_payment', 'waiver')),
  amount integer not null,
  currency text not null,
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index studio_fee_ledger_studio_idx on public.studio_fee_ledger (studio_id, created_at desc);
create unique index studio_fee_ledger_commission_once on public.studio_fee_ledger (booking_id) where kind = 'cash_commission';
create unique index studio_fee_ledger_offset_once on public.studio_fee_ledger (payout_id) where kind = 'payout_offset';

create table public.studio_fee_invoices (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  amount integer not null check (amount > 0),
  currency text not null,
  stripe_invoice_id text unique,
  hosted_invoice_url text,
  status text not null default 'open' check (status in ('open', 'paid', 'void')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create view public.studio_fee_balances with (security_invoker = true) as
select l.studio_id, s.name as studio_name, l.currency, sum(l.amount)::int as balance,
  max(l.created_at) filter (where l.kind = 'cash_commission') as last_commission_at
from public.studio_fee_ledger l join public.studios s on s.id = l.studio_id
group by l.studio_id, s.name, l.currency;

alter table public.studio_fee_ledger enable row level security;
alter table public.studio_fee_invoices enable row level security;
create policy "fee_ledger: owner or admin read" on public.studio_fee_ledger for select
  using (public.owns_studio(studio_id) or public.is_admin());
create policy "fee_invoices: owner or admin read" on public.studio_fee_invoices for select
  using (public.owns_studio(studio_id) or public.is_admin());

-- A completed cash session makes the platform fee payable.
create or replace function public.on_cash_booking_completed()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new.payment_method = 'cash' then
    insert into public.studio_fee_ledger (studio_id, booking_id, kind, amount, currency, note)
    values (new.studio_id, new.id, 'cash_commission', (new.price ->> 'studio_commission')::int, new.price ->> 'currency',
            'Platform fee for cash booking ' || new.reference)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
create trigger on_cash_booking_completed after update of status on public.bookings
  for each row execute function public.on_cash_booking_completed();

-- Studio confirms it received the cash.
create or replace function public.mark_cash_received(p_booking_id uuid)
returns public.bookings
language plpgsql security definer set search_path = public
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then raise exception 'not_found'; end if;
  if not public.owns_approved_studio(b.studio_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if b.payment_method is distinct from 'cash' then raise exception 'This booking was paid by card.'; end if;
  if b.status not in ('confirmed', 'completed') or b.starts_at > now() then
    raise exception 'You can confirm cash once the session has started.';
  end if;
  update public.bookings set payment_status = 'paid', cash_received_at = now(), changed_by = auth.uid()
  where id = b.id returning * into b;
  return b;
end;
$$;

-- Cash bookings not confirmed by the studio are treated as paid 3 days after the session
-- (the studio can open a dispute before that, e.g. for a no-show).
create or replace function public.run_cash_housekeeping()
returns void
language sql security definer set search_path = public
as $$
  update public.bookings set payment_status = 'paid', cash_received_at = coalesce(cash_received_at, now())
  where payment_method = 'cash' and payment_status = 'pay_at_studio'
    and status = 'completed' and ends_at < now() - interval '3 days';
$$;
select cron.schedule('sonora-cash-housekeeping', '17 * * * *', $$select public.run_cash_housekeeping()$$);

-- ---------------------------------------------------------------------------
-- Terms acceptance (records version + time; required before using the app)
-- ---------------------------------------------------------------------------
create or replace function public.accept_terms(p_version text)
returns public.profiles
language plpgsql security definer set search_path = public
as $$
declare
  p public.profiles;
begin
  if coalesce(trim(p_version), '') = '' then raise exception 'Missing terms version.'; end if;
  update public.profiles set accepted_terms_version = p_version, accepted_terms_at = now()
  where id = auth.uid() returning * into p;
  if p.id is null then raise exception 'not_found'; end if;
  return p;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: settle or waive fees
-- ---------------------------------------------------------------------------
create or replace function public.admin_record_fee_settlement(p_studio_id uuid, p_amount integer, p_currency text, p_kind text, p_note text default null)
returns public.studio_fee_ledger
language plpgsql security definer set search_path = public
as $$
declare
  row public.studio_fee_ledger;
begin
  perform public.require_admin();
  if p_kind not in ('manual_payment', 'waiver') then raise exception 'Use manual_payment or waiver.'; end if;
  if p_amount <= 0 then raise exception 'Amount must be positive.'; end if;
  insert into public.studio_fee_ledger (studio_id, kind, amount, currency, note, created_by)
  values (p_studio_id, p_kind, -p_amount, upper(p_currency), p_note, auth.uid())
  returning * into row;
  return row;
end;
$$;

-- Keep the studio informed about what it owes.
create or replace function public.on_fee_ledger_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  owner uuid;
begin
  select owner_id into owner from public.studios where id = new.studio_id;
  if new.kind = 'cash_commission' then
    perform public.notify(owner, 'system', 'Platform fee added',
      public.format_money(new.amount, new.currency) || ' for a cash booking. It will be deducted from your next payout.', new.booking_id, null, new.studio_id);
  elsif new.kind in ('invoice_payment', 'manual_payment') then
    perform public.notify(owner, 'system', 'Payment received', 'Thanks! We received ' || public.format_money(-new.amount, new.currency) || ' in platform fees.', null, null, new.studio_id);
  end if;
  return new;
end;
$$;
create trigger on_fee_ledger_insert after insert on public.studio_fee_ledger
  for each row execute function public.on_fee_ledger_insert();
