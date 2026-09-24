-- Sonora: core schema
-- Money is stored as integer minor units (cents). Timestamps are timestamptz.
-- Nested listing data is jsonb with snake_case keys (matches the iOS encoder).

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('artist', 'studio_owner', 'admin');
create type public.account_status as enum ('active', 'suspended', 'banned');
create type public.studio_status as enum ('draft', 'pending_review', 'changes_requested', 'approved', 'rejected', 'suspended');
create type public.booking_status as enum ('awaiting_payment', 'pending_approval', 'confirmed', 'declined', 'cancelled', 'completed', 'disputed', 'expired');
create type public.payment_status as enum ('unpaid', 'authorized', 'deposit_paid', 'paid', 'partially_refunded', 'refunded', 'failed');
create type public.payment_method as enum ('card', 'apple_pay', 'google_pay');
create type public.transaction_kind as enum ('charge', 'balance', 'refund');
create type public.transaction_status as enum ('pending', 'succeeded', 'failed');
create type public.payout_status as enum ('scheduled', 'in_transit', 'paid', 'failed');
create type public.message_kind as enum ('text', 'system', 'booking');
create type public.report_target as enum ('user', 'studio', 'review', 'message', 'booking');
create type public.report_reason as enum ('fake', 'spam', 'abusive', 'inappropriate', 'fraud', 'no_show', 'other');
create type public.report_status as enum ('open', 'resolved', 'dismissed');
create type public.notification_kind as enum (
  'booking_confirmed', 'booking_changed', 'booking_cancelled', 'booking_declined', 'session_reminder',
  'refund_issued', 'review_reminder', 'booking_requested', 'new_review', 'payout_sent',
  'studio_approved', 'studio_rejected', 'studio_changes_requested', 'new_message', 'system'
);

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role public.user_role not null default 'artist',
  status public.account_status not null default 'active',
  status_reason text,
  is_verified boolean not null default false,
  settings jsonb not null default '{}'::jsonb,
  stripe_customer_id text,
  created_at timestamptz not null default now()
);

create table public.artist_profiles (
  id uuid primary key references public.profiles (id) on delete cascade,
  artist_name text not null default '',
  genres text[] not null default '{}',
  city text not null default '',
  bio text not null default '',
  avatar_url text,
  links jsonb not null default '[]'::jsonb,
  is_verified boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'ios',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Studios
-- ---------------------------------------------------------------------------
create table public.studios (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null default '',
  tagline text not null default '',
  description text not null default '',
  photo_urls text[] not null default '{}',
  video_url text,
  address jsonb not null default '{"street":"","postal_code":"","city":"","area":"","country":""}'::jsonb,
  latitude double precision not null default 0,
  longitude double precision not null default 0,
  contact jsonb not null default '{"phone":"","email":"","website":""}'::jsonb,
  timezone text not null default 'Europe/Athens',
  currency text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  price_from integer not null default 0 check (price_from >= 0),
  session_types jsonb not null default '[]'::jsonb,
  add_ons jsonb not null default '[]'::jsonb,
  facilities text[] not null default '{}',
  equipment jsonb not null default '[]'::jsonb,
  engineers jsonb not null default '[]'::jsonb,
  capacity integer not null default 4 check (capacity > 0),
  genres text[] not null default '{}',
  opening_hours jsonb not null default '[]'::jsonb,
  rules text[] not null default '{}',
  booking_policy jsonb not null default '{}'::jsonb,
  status public.studio_status not null default 'draft',
  is_active boolean not null default false,
  is_verified boolean not null default false,
  admin_note text,
  rating_average double precision not null default 0,
  review_count integer not null default 0,
  booking_count integer not null default 0,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id)
);

create index studios_public_idx on public.studios (status, is_active);
create index studios_owner_idx on public.studios (owner_id);
create index studios_city_idx on public.studios ((address ->> 'city'));

-- Audit trail of moderation decisions.
create table public.studio_status_events (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  from_status public.studio_status,
  to_status public.studio_status not null,
  note text,
  actor_id uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.studio_payout_accounts (
  studio_id uuid primary key references public.studios (id) on delete cascade,
  account_holder text not null default '',
  iban_last4 text not null default '',
  stripe_account_id text,
  payouts_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.blocked_slots (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null default '',
  check (ends_at > starts_at)
);
create index blocked_slots_studio_idx on public.blocked_slots (studio_id, starts_at);

-- ---------------------------------------------------------------------------
-- Bookings & money
-- ---------------------------------------------------------------------------
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  artist_id uuid not null references public.profiles (id),
  studio_id uuid not null references public.studios (id),
  artist_name text not null,
  studio_name text not null,
  session_type_id text not null,
  session_type_name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  hours integer not null check (hours between 1 and 24),
  add_ons jsonb not null default '[]'::jsonb,
  status public.booking_status not null default 'awaiting_payment',
  payment_status public.payment_status not null default 'unpaid',
  price jsonb not null,
  notes text not null default '',
  cancellation_reason text,
  cancelled_by public.user_role,
  refund_amount integer not null default 0,
  has_review boolean not null default false,
  payment_intent_id text,
  balance_payment_intent_id text,
  payment_method public.payment_method,
  -- Who made the last change (set by edge functions) so triggers notify the other party.
  changed_by uuid,
  reminder_24h_sent_at timestamptz,
  reminder_2h_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  -- The database itself guarantees no double bookings.
  constraint bookings_no_overlap exclude using gist (
    studio_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('awaiting_payment', 'pending_approval', 'confirmed'))
);
create index bookings_artist_idx on public.bookings (artist_id, starts_at desc);
create index bookings_studio_idx on public.bookings (studio_id, starts_at desc);
create index bookings_status_idx on public.bookings (status, starts_at);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  studio_id uuid not null references public.studios (id),
  artist_id uuid not null references public.profiles (id),
  kind public.transaction_kind not null,
  method public.payment_method not null default 'card',
  status public.transaction_status not null default 'pending',
  amount integer not null check (amount >= 0),
  platform_fee integer not null default 0,
  currency text not null,
  receipt_number text not null unique default ('RCPT-' || upper(substr(md5(gen_random_uuid()::text), 1, 10))),
  card_brand text,
  card_last4 text,
  failure_reason text,
  provider_reference text,
  created_at timestamptz not null default now()
);
create index transactions_booking_idx on public.transactions (booking_id);
create unique index transactions_provider_ref_idx on public.transactions (provider_reference, kind);

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references public.studios (id),
  amount integer not null,
  currency text not null,
  status public.payout_status not null default 'scheduled',
  scheduled_for timestamptz not null,
  paid_at timestamptz,
  booking_ids uuid[] not null default '{}',
  provider_reference text,
  failure_reason text,
  created_at timestamptz not null default now()
);
create index payouts_studio_idx on public.payouts (studio_id, scheduled_for desc);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  opened_by uuid not null references public.profiles (id),
  reason text not null,
  status public.report_status not null default 'open',
  resolution text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Communication
-- ---------------------------------------------------------------------------
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.profiles (id) on delete cascade,
  studio_id uuid not null references public.studios (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete set null,
  artist_name text not null,
  studio_name text not null,
  studio_photo_url text,
  last_message_preview text not null default '',
  last_message_at timestamptz not null default now(),
  artist_unread integer not null default 0,
  studio_unread integer not null default 0,
  created_at timestamptz not null default now()
);
-- One thread per artist+studio(+booking). Chat is always scoped; there is no free social messaging.
create unique index conversations_scope_idx on public.conversations (artist_id, studio_id, coalesce(booking_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  kind public.message_kind not null default 'text',
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  booking_id uuid references public.bookings (id) on delete set null,
  conversation_id uuid references public.conversations (id) on delete set null,
  studio_id uuid references public.studios (id) on delete set null,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Reviews & moderation
-- ---------------------------------------------------------------------------
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id),
  studio_id uuid not null references public.studios (id) on delete cascade,
  artist_id uuid not null references public.profiles (id) on delete cascade,
  artist_name text not null,
  rating integer not null check (rating between 1 and 5),
  facilities_rating integer not null check (facilities_rating between 1 and 5),
  experience_rating integer not null check (experience_rating between 1 and 5),
  engineer_rating integer check (engineer_rating between 1 and 5),
  text text not null default '',
  studio_reply text,
  studio_replied_at timestamptz,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index reviews_studio_idx on public.reviews (studio_id, created_at desc);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type public.report_target not null,
  target_id uuid not null,
  reason public.report_reason not null,
  details text not null default '',
  status public.report_status not null default 'open',
  admin_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index reports_status_idx on public.reports (status, created_at desc);

-- Commercial settings (mirrored in supabase/functions/_shared/pricing.ts).
create table public.platform_settings (
  key text primary key,
  value jsonb not null
);
insert into public.platform_settings (key, value) values
  ('artist_service_fee_percent', '8'),
  ('studio_commission_percent', '5'),
  ('payout_delay_days', '2');
