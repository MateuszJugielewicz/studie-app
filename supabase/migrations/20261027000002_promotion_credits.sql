-- Promotion credits: 1 credit = €1. Admins can give credits, studios and artists can buy them on the
-- website (credits-payment, Stripe), and they pay for promotions (studio or artist) instead of a card.
-- The balance is the sum of a ledger, so every grant, purchase and spend can be traced.

create table if not exists public.promotion_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  amount integer not null check (amount <> 0),            -- credits; positive adds, negative spends
  kind text not null check (kind in ('grant', 'purchase', 'spend', 'refund', 'adjust')),
  note text,
  promotion_id uuid references public.studio_promotions (id) on delete set null,
  payment_intent_id text unique,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists promotion_credit_ledger_user on public.promotion_credit_ledger (user_id, created_at desc);
alter table public.promotion_credit_ledger enable row level security;
create policy "promotion_credit_ledger: own or admin read" on public.promotion_credit_ledger for select
  using (user_id = auth.uid() or public.is_admin());
revoke all on public.promotion_credit_ledger from anon;
grant select on public.promotion_credit_ledger to authenticated;

-- Card purchases of credits (the payment itself is in Stripe).
create table if not exists public.credit_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  credits integer not null check (credits between 1 and 1000),
  amount integer not null,                                 -- minor units (EUR cents)
  currency text not null default 'EUR',
  status text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  payment_intent_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists credit_purchases_user on public.credit_purchases (user_id, created_at desc);
alter table public.credit_purchases enable row level security;
create policy "credit_purchases: own or admin read" on public.credit_purchases for select
  using (user_id = auth.uid() or public.is_admin());
revoke all on public.credit_purchases from anon;
grant select on public.credit_purchases to authenticated;

alter table public.studio_promotions add column if not exists credits_used integer not null default 0;

-- What a package costs in credits: the euro price (1 credit = €1).
create or replace function public.promotion_credit_cost(p_package text)
returns integer language sql immutable as $$
  select public.promotion_price(p_package, 'EUR') / 100;
$$;

create or replace function public.promotion_credit_balance(p_user_id uuid default null)
returns integer
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(l.amount), 0)::int from public.promotion_credit_ledger l
  where l.user_id = coalesce(p_user_id, auth.uid())
    and (coalesce(p_user_id, auth.uid()) = auth.uid() or public.is_admin());
$$;
revoke execute on function public.promotion_credit_balance(uuid) from public, anon;
grant execute on function public.promotion_credit_balance(uuid) to authenticated;

-- Pays an ordered (pending) promotion with credits and starts it.
create or replace function public.pay_promotion_with_credits(p_promotion_id uuid)
returns public.studio_promotions
language plpgsql security definer set search_path = public
as $$
declare
  v_promo public.studio_promotions := (select p from public.studio_promotions p where p.id = p_promotion_id);
  v_cost integer;
begin
  if v_promo.id is null
     or not ((v_promo.studio_id is not null and public.owns_studio(v_promo.studio_id)) or v_promo.artist_id = auth.uid()) then
    raise exception 'not_found';
  end if;
  if v_promo.status <> 'pending' or v_promo.source <> 'purchase' then raise exception 'This promotion is no longer awaiting payment.'; end if;
  v_cost := public.promotion_credit_cost(v_promo.package);
  if v_cost is null or v_cost <= 0 then raise exception 'Unknown promotion package.'; end if;
  -- One spend at a time per person, so the balance can't be used twice.
  perform pg_advisory_xact_lock(hashtext('promotion-credits:' || auth.uid()::text));
  if public.promotion_credit_balance(auth.uid()) < v_cost then raise exception 'Not enough credits.'; end if;
  insert into public.promotion_credit_ledger (user_id, amount, kind, note, promotion_id, created_by)
  values (auth.uid(), -v_cost, 'spend', 'Promotion · ' || v_promo.days || ' days', v_promo.id, auth.uid());
  update public.studio_promotions set credits_used = v_cost, amount = v_cost * 100, currency = 'EUR' where id = v_promo.id;
  return public.activate_promotion(v_promo.id);
end;
$$;
revoke execute on function public.pay_promotion_with_credits(uuid) from public, anon;
grant execute on function public.pay_promotion_with_credits(uuid) to authenticated;

-- Admin: add (or, with a negative amount, remove) credits. The person is notified when credits are added.
create or replace function public.admin_adjust_credits(p_user_id uuid, p_amount integer, p_note text default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_balance integer;
begin
  perform public.require_admin();
  if p_amount is null or p_amount = 0 or abs(p_amount) > 10000 then raise exception 'Enter between 1 and 10000 credits.'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.role in ('artist', 'studio_owner')) then
    raise exception 'Credits can only be given to artists and studio owners.';
  end if;
  perform pg_advisory_xact_lock(hashtext('promotion-credits:' || p_user_id::text));
  v_balance := public.promotion_credit_balance(p_user_id);
  if v_balance + p_amount < 0 then raise exception 'They only have % credits.', v_balance; end if;
  insert into public.promotion_credit_ledger (user_id, amount, kind, note, created_by)
  values (p_user_id, p_amount, case when p_amount > 0 then 'grant' else 'adjust' end, nullif(btrim(coalesce(p_note, '')), ''), auth.uid());
  if p_amount > 0 then
    perform public.notify(p_user_id, 'system', 'You received promotion credits',
      p_amount || ' credits were added to your account (1 credit = €1). Use them to promote yourself on EasySesh.',
      null, null, null);
  end if;
  return v_balance + p_amount;
end;
$$;
revoke execute on function public.admin_adjust_credits(uuid, integer, text) from public, anon;
grant execute on function public.admin_adjust_credits(uuid, integer, text) to authenticated;

-- A paid card purchase becomes credits (only the server calls this, after Stripe confirms the payment).
create or replace function public.complete_credit_purchase(p_purchase_id uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_purchase public.credit_purchases;
begin
  select * into v_purchase from public.credit_purchases c where c.id = p_purchase_id for update;
  if v_purchase.id is null then raise exception 'not_found'; end if;
  if v_purchase.status = 'pending' then
    update public.credit_purchases set status = 'paid', paid_at = now() where id = v_purchase.id;
    insert into public.promotion_credit_ledger (user_id, amount, kind, note, payment_intent_id, created_by)
    values (v_purchase.user_id, v_purchase.credits, 'purchase', 'Bought ' || v_purchase.credits || ' credits',
            v_purchase.payment_intent_id, v_purchase.user_id)
    on conflict (payment_intent_id) do nothing;
  end if;
  return (select coalesce(sum(l.amount), 0)::int from public.promotion_credit_ledger l where l.user_id = v_purchase.user_id);
end;
$$;
revoke execute on function public.complete_credit_purchase(uuid) from public, anon, authenticated;

-- Admin panel: everyone with credits (or credit history), with their balance.
create or replace view public.admin_credit_balances with (security_invoker = true) as
select l.user_id, p.email, p.role,
  coalesce(nullif(a.artist_name, ''), (select s.name from public.studios s where s.owner_id = p.id limit 1), p.email) as name,
  sum(l.amount)::int as balance,
  sum(l.amount) filter (where l.amount > 0 and l.kind = 'grant')::int as granted,
  sum(l.amount) filter (where l.kind = 'purchase')::int as bought,
  (-sum(l.amount) filter (where l.kind = 'spend'))::int as spent,
  max(l.created_at) as last_activity
from public.promotion_credit_ledger l
join public.profiles p on p.id = l.user_id
left join public.artist_profiles a on a.id = l.user_id
group by l.user_id, p.email, p.role, a.artist_name, p.id;
grant select on public.admin_credit_balances to authenticated;
revoke all on public.admin_credit_balances from anon;

-- The promotions list also shows what was paid in credits (new columns go at the end).
create or replace view public.admin_promotions with (security_invoker = true) as
select p.id, p.studio_id, p.package, p.days, p.amount, p.currency, p.status, p.source, p.payment_intent_id,
       p.starts_at, p.ends_at, p.note, p.created_by, p.created_at,
       coalesce(s.name, a.artist_name || ' (artist)') as studio_name, coalesce(s.promoted_until, a.promoted_until) as promoted_until,
       p.artist_id, p.credits_used
from public.studio_promotions p
left join public.studios s on s.id = p.studio_id
left join public.artist_profiles a on a.id = p.artist_id;
