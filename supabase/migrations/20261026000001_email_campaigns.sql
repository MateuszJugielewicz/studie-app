-- Email campaigns (owners only): one message sent separately to a list of addresses, with
-- {{name}}, {{city}} and {{website}} filled in per recipient. Campaigns are drafts until an owner
-- sends a batch from the admin panel (admin-campaign-send); nothing is sent automatically.
-- Addresses that asked not to be contacted go on email_suppressions and are always skipped.

create table if not exists public.email_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  from_local text not null default 'easysesh' check (from_local ~ '^[a-z0-9][a-z0-9._-]{0,40}$'),
  subject text not null default '' check (char_length(subject) <= 200),
  body text not null default '' check (char_length(body) <= 20000),
  -- Small print under the email (e.g. why they got it and how to opt out), in the campaign's language.
  footer text not null default '' check (char_length(footer) <= 1000),
  note text not null default '' check (char_length(note) <= 4000),
  status text not null default 'draft' check (status in ('draft', 'sending', 'done')),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.email_campaign_recipients (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.email_campaigns (id) on delete cascade,
  email text not null check (email ~* '^[^\s@<>,;"]+@[^\s@<>,;"]+\.[a-z]{2,}$'),
  name text not null default '',
  city text not null default '',
  website text not null default '',
  source text not null default '',
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'skipped')),
  error text,
  resend_id text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists email_campaign_recipients_unique on public.email_campaign_recipients (campaign_id, lower(email));
create index if not exists email_campaign_recipients_pending on public.email_campaign_recipients (campaign_id) where status = 'pending';

create table if not exists public.email_suppressions (
  email text primary key check (email = lower(email)),
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.email_campaigns enable row level security;
alter table public.email_campaign_recipients enable row level security;
alter table public.email_suppressions enable row level security;

create policy "email_campaigns: owners" on public.email_campaigns for all
  using (public.has_admin_rank('owner')) with check (public.has_admin_rank('owner'));
create policy "email_campaign_recipients: owners" on public.email_campaign_recipients for all
  using (public.has_admin_rank('owner')) with check (public.has_admin_rank('owner'));
create policy "email_suppressions: owners" on public.email_suppressions for all
  using (public.has_admin_rank('owner')) with check (public.has_admin_rank('owner'));

revoke all on public.email_campaigns, public.email_campaign_recipients, public.email_suppressions from anon;
grant select, insert, update, delete on public.email_campaigns, public.email_campaign_recipients, public.email_suppressions to authenticated;

create or replace function public.touch_email_campaign()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists touch_email_campaign on public.email_campaigns;
create trigger touch_email_campaign before update on public.email_campaigns for each row execute function public.touch_email_campaign();

-- Campaign list with how far each one got.
create or replace view public.admin_email_campaigns with (security_invoker = true) as
select c.*,
  count(r.id) filter (where r.status = 'pending') as pending_count,
  count(r.id) filter (where r.status = 'sent') as sent_count,
  count(r.id) filter (where r.status = 'failed') as failed_count,
  count(r.id) filter (where r.status = 'skipped') as skipped_count
from public.email_campaigns c
left join public.email_campaign_recipients r on r.campaign_id = c.id
group by c.id;
grant select on public.admin_email_campaigns to authenticated;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'zz_staff_write_audit' and tgrelid = 'public.email_campaigns'::regclass) then
    create trigger zz_staff_write_audit after insert or update or delete on public.email_campaigns for each row execute function public.staff_write_audit();
  end if;
end $$;
