-- Sonora: RPCs used by the app and triggers that keep derived data + notifications in sync.

-- ---------------------------------------------------------------------------
-- Notifications helper
-- ---------------------------------------------------------------------------
create or replace function public.notify(
  p_user_id uuid,
  p_kind public.notification_kind,
  p_title text,
  p_body text,
  p_booking_id uuid default null,
  p_conversation_id uuid default null,
  p_studio_id uuid default null
) returns void
language sql security definer set search_path = public
as $$
  insert into public.notifications (user_id, kind, title, body, booking_id, conversation_id, studio_id)
  select p_user_id, p_kind, p_title, p_body, p_booking_id, p_conversation_id, p_studio_id
  where p_user_id is not null;
$$;
revoke execute on function public.notify from public, anon, authenticated;

create or replace function public.format_local(p_at timestamptz, p_studio_id uuid)
returns text language sql stable security definer set search_path = public
as $$
  select to_char(p_at at time zone coalesce((select timezone from public.studios where id = p_studio_id), 'UTC'), 'Dy DD Mon, HH24:MI');
$$;

create or replace function public.format_money(p_amount integer, p_currency text)
returns text language sql immutable
as $$
  select p_currency || ' ' || to_char(p_amount / 100.0, 'FM999999990.00');
$$;

-- Adds a system line to every conversation tied to a booking.
create or replace function public.booking_system_message(p_booking_id uuid, p_body text)
returns void
language sql security definer set search_path = public
as $$
  insert into public.messages (conversation_id, sender_id, kind, body)
  select id, null, 'system', p_body from public.conversations where booking_id = p_booking_id;
$$;
revoke execute on function public.booking_system_message from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Studios
-- ---------------------------------------------------------------------------
create or replace function public.studio_validation_problems(s public.studios)
returns text[]
language plpgsql stable
as $$
declare
  problems text[] := '{}';
begin
  if char_length(trim(s.name)) < 3 then problems := problems || 'Add your studio''s name.'; end if;
  if char_length(s.description) < 40 then problems := problems || 'Write a description of at least 40 characters.'; end if;
  if cardinality(s.photo_urls) = 0 then problems := problems || 'Add at least one photo.'; end if;
  if coalesce(s.address ->> 'street', '') = '' or coalesce(s.address ->> 'city', '') = '' then problems := problems || 'Add the studio''s address.'; end if;
  if s.latitude = 0 and s.longitude = 0 then problems := problems || 'Place your studio on the map.'; end if;
  if coalesce(s.contact ->> 'email', '') = '' and coalesce(s.contact ->> 'phone', '') = '' then problems := problems || 'Add an email or phone number.'; end if;
  if jsonb_array_length(s.session_types) = 0 or exists (
       select 1 from jsonb_array_elements(s.session_types) as t where coalesce((t.value ->> 'hourly_rate')::int, 0) <= 0) then
    problems := problems || 'Set a price for each session type.';
  end if;
  if not exists (select 1 from jsonb_array_elements(s.opening_hours) as h where not coalesce((h.value ->> 'is_closed')::boolean, false)) then
    problems := problems || 'Set your opening hours.';
  end if;
  if cardinality(s.genres) = 0 then problems := problems || 'Pick at least one genre.'; end if;
  return problems;
end;
$$;

create or replace function public.submit_studio_for_review(p_studio_id uuid)
returns public.studios
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios;
  problems text[];
begin
  select * into s from public.studios where id = p_studio_id and owner_id = auth.uid() for update;
  if s.id is null then raise exception 'not_found'; end if;
  if s.status not in ('draft', 'changes_requested', 'rejected') then return s; end if;
  problems := public.studio_validation_problems(s);
  if cardinality(problems) > 0 then raise exception '%', problems[1]; end if;

  insert into public.studio_status_events (studio_id, from_status, to_status, actor_id)
  values (s.id, s.status, 'pending_review', auth.uid());
  update public.studios set status = 'pending_review', submitted_at = now() where id = s.id returning * into s;
  return s;
end;
$$;

create or replace function public.set_studio_active(p_studio_id uuid, p_active boolean)
returns public.studios
language plpgsql security definer set search_path = public
as $$
declare
  s public.studios;
begin
  select * into s from public.studios where id = p_studio_id and owner_id = auth.uid();
  if s.id is null then raise exception 'not_found'; end if;
  if s.status <> 'approved' then raise exception 'Your studio must be approved before it can go live.'; end if;
  update public.studios set is_active = p_active where id = s.id returning * into s;
  return s;
end;
$$;

-- Occupied time ranges for availability. Exposes no personal data.
create or replace function public.studio_busy_intervals(p_studio_ids uuid[], p_from timestamptz, p_to timestamptz)
returns table (studio_id uuid, starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select b.studio_id, b.starts_at, b.ends_at from public.bookings b
  where b.studio_id = any (p_studio_ids)
    and b.status in ('awaiting_payment', 'pending_approval', 'confirmed')
    and b.starts_at < p_to and b.ends_at > p_from
  union all
  select s.studio_id, s.starts_at, s.ends_at from public.blocked_slots s
  where s.studio_id = any (p_studio_ids) and s.starts_at < p_to and s.ends_at > p_from;
$$;

create or replace function public.on_studio_status_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'approved' then
      perform public.notify(new.owner_id, 'studio_approved', 'Your studio is live 🎉', new.name || ' was approved and is now visible to artists.', null, null, new.id);
    elsif new.status = 'rejected' then
      perform public.notify(new.owner_id, 'studio_rejected', 'Application not approved', coalesce(new.admin_note, 'Your studio was not approved.'), null, null, new.id);
    elsif new.status = 'changes_requested' then
      perform public.notify(new.owner_id, 'studio_changes_requested', 'Changes requested', coalesce(new.admin_note, 'Please update your listing and resubmit.'), null, null, new.id);
    elsif new.status = 'suspended' then
      perform public.notify(new.owner_id, 'system', 'Studio suspended', coalesce(new.admin_note, 'Your studio has been suspended. Contact support.'), null, null, new.id);
    end if;
  end if;
  return new;
end;
$$;
create trigger on_studio_status_change after update of status on public.studios
  for each row execute function public.on_studio_status_change();

-- ---------------------------------------------------------------------------
-- Bookings → notifications, system messages, counters
-- ---------------------------------------------------------------------------
create or replace function public.on_booking_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  owner uuid;
  when_text text;
begin
  select owner_id into owner from public.studios where id = new.studio_id;
  when_text := public.format_local(new.starts_at, new.studio_id);

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    case new.status
      when 'pending_approval' then
        perform public.notify(owner, 'booking_requested', 'New booking request',
          new.artist_name || ' wants to book ' || new.hours || 'h on ' || when_text || '. Accept or decline.', new.id);
      when 'confirmed' then
        perform public.notify(new.artist_id, 'booking_confirmed', 'Booking confirmed ✅', new.studio_name || ' · ' || when_text, new.id);
        if old.status = 'awaiting_payment' then
          perform public.notify(owner, 'booking_requested', 'New booking', new.artist_name || ' booked ' || new.hours || 'h on ' || when_text || '.', new.id);
        end if;
        update public.studios set booking_count = booking_count + 1 where id = new.studio_id;
      when 'declined' then
        perform public.notify(new.artist_id, 'booking_declined', 'Request declined',
          new.studio_name || ' couldn''t take your session. Your card was not charged.' || coalesce(' “' || new.cancellation_reason || '”', ''), new.id);
      when 'cancelled' then
        if new.cancelled_by = 'artist' then
          perform public.notify(owner, 'booking_cancelled', 'Booking cancelled', new.artist_name || ' cancelled the session on ' || when_text || '.', new.id);
        else
          perform public.notify(new.artist_id, 'booking_cancelled', 'Booking cancelled by studio',
            new.studio_name || ' cancelled your session on ' || when_text || '. You''ll get a full refund.', new.id);
        end if;
        perform public.booking_system_message(new.id, 'Booking ' || new.reference || ' was cancelled by the ' || case when new.cancelled_by = 'artist' then 'artist' else 'studio' end || '.');
      when 'completed' then
        perform public.notify(new.artist_id, 'review_reminder', 'How was ' || new.studio_name || '?', 'Leave a review for your session.', new.id, null, new.studio_id);
      when 'disputed' then
        perform public.notify(owner, 'system', 'Problem reported', 'A problem was reported on booking ' || new.reference || '. Our team will contact you.', new.id);
      else
        null;
    end case;
  end if;

  if tg_op = 'UPDATE' and new.starts_at is distinct from old.starts_at and new.status = 'confirmed' then
    perform public.notify(case when new.changed_by = new.artist_id then owner else new.artist_id end, 'booking_changed', 'Booking moved',
      new.reference || ' moved from ' || public.format_local(old.starts_at, new.studio_id) || ' to ' || when_text || '.', new.id);
    perform public.booking_system_message(new.id, 'Booking moved from ' || public.format_local(old.starts_at, new.studio_id) || ' to ' || when_text || '.');
  end if;

  if tg_op = 'UPDATE' and new.refund_amount > old.refund_amount and new.payment_status in ('refunded', 'partially_refunded') and old.payment_status <> 'authorized' then
    perform public.notify(new.artist_id, 'refund_issued', 'Refund on its way',
      public.format_money(new.refund_amount - old.refund_amount, new.price ->> 'currency') || ' will be back on your card in 5–10 days.', new.id);
  end if;

  return new;
end;
$$;
create trigger on_booking_change after update on public.bookings
  for each row execute function public.on_booking_change();

create or replace function public.open_dispute(p_booking_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id;
  if b.id is null then raise exception 'not_found'; end if;
  if b.artist_id <> auth.uid() and not public.owns_studio(b.studio_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if b.status not in ('confirmed', 'completed') then raise exception 'You can only report a problem on a confirmed or completed booking.'; end if;
  insert into public.disputes (booking_id, opened_by, reason) values (b.id, auth.uid(), p_reason);
  update public.bookings set status = 'disputed', changed_by = auth.uid() where id = b.id;
  perform public.notify(auth.uid(), 'system', 'We''re on it', 'Our team will review booking ' || b.reference || ' within 24 hours.', b.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create or replace function public.get_or_create_conversation(p_studio_id uuid, p_booking_id uuid default null)
returns public.conversations
language plpgsql security definer set search_path = public
as $$
declare
  me public.profiles;
  s public.studios;
  b public.bookings;
  artist uuid;
  convo public.conversations;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.status <> 'active' then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into s from public.studios where id = p_studio_id;
  if s.id is null then raise exception 'not_found'; end if;

  if p_booking_id is not null then
    select * into b from public.bookings where id = p_booking_id and studio_id = p_studio_id;
    if b.id is null then raise exception 'not_found'; end if;
  end if;

  if me.role = 'artist' then
    if p_booking_id is null and not (s.status = 'approved' and s.is_active) then raise exception 'not_found'; end if;
    if b.id is not null and b.artist_id <> me.id then raise exception 'forbidden' using errcode = '42501'; end if;
    artist := me.id;
  elsif s.owner_id = me.id and b.id is not null and public.owns_approved_studio(s.id) then
    -- Studios can only start a conversation about one of their bookings.
    artist := b.artist_id;
  else
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into convo from public.conversations
  where artist_id = artist and studio_id = s.id and booking_id is not distinct from p_booking_id;
  if convo.id is not null then return convo; end if;

  insert into public.conversations (artist_id, studio_id, booking_id, artist_name, studio_name, studio_photo_url)
  values (
    artist, s.id, p_booking_id,
    coalesce(nullif((select artist_name from public.artist_profiles where id = artist), ''), 'Artist'),
    s.name, s.photo_urls[1]
  )
  returning * into convo;
  return convo;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.conversations c set
    artist_unread = case when c.artist_id = auth.uid() then 0 else c.artist_unread end,
    studio_unread = case when public.owns_studio(c.studio_id) then 0 else c.studio_unread end
  where c.id = p_conversation_id;
end;
$$;

create or replace function public.on_message_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  c public.conversations;
  owner uuid;
  from_artist boolean;
begin
  select * into c from public.conversations where id = new.conversation_id;
  select owner_id into owner from public.studios where id = c.studio_id;
  from_artist := new.sender_id = c.artist_id;

  update public.conversations set
    last_message_preview = left(new.body, 140),
    last_message_at = new.created_at,
    artist_unread = artist_unread + case when new.sender_id is null or not from_artist then 1 else 0 end,
    studio_unread = studio_unread + case when new.sender_id is null or from_artist then 1 else 0 end
  where id = c.id;

  if new.kind = 'text' then
    perform public.notify(
      case when from_artist then owner else c.artist_id end,
      'new_message',
      case when from_artist then c.artist_name else c.studio_name end,
      left(new.body, 140),
      c.booking_id, c.id
    );
  end if;
  return new;
end;
$$;
create trigger on_message_insert after insert on public.messages
  for each row execute function public.on_message_insert();

-- ---------------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER on purpose: is_trusted() must see the real caller.
create or replace function public.before_review_insert()
returns trigger
language plpgsql
as $$
begin
  new.artist_name := coalesce(nullif((select artist_name from public.artist_profiles where id = new.artist_id), ''), new.artist_name);
  if not public.is_trusted() then
    new.studio_reply := null;
    new.studio_replied_at := null;
    new.is_hidden := false;
    new.created_at := now();
  end if;
  return new;
end;
$$;
create trigger before_review_insert before insert on public.reviews
  for each row execute function public.before_review_insert();

create or replace function public.refresh_studio_rating(p_studio_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.studios s set
    rating_average = coalesce((select round(avg(rating)::numeric, 1) from public.reviews r where r.studio_id = s.id and not r.is_hidden), 0),
    review_count = (select count(*) from public.reviews r where r.studio_id = s.id and not r.is_hidden)
  where s.id = p_studio_id;
$$;

create or replace function public.after_review_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  owner uuid;
begin
  perform public.refresh_studio_rating(new.studio_id);
  if tg_op = 'INSERT' then
    update public.bookings set has_review = true where id = new.booking_id;
    select owner_id into owner from public.studios where id = new.studio_id;
    perform public.notify(owner, 'new_review', 'New ' || new.rating || '★ review',
      new.artist_name || ' reviewed your studio.', new.booking_id, null, new.studio_id);
  end if;
  return new;
end;
$$;
create trigger after_review_insert after insert on public.reviews
  for each row execute function public.after_review_change();
create trigger after_review_visibility after update of is_hidden on public.reviews
  for each row execute function public.after_review_change();

create or replace function public.reply_to_review(p_review_id uuid, p_reply text)
returns public.reviews
language plpgsql security definer set search_path = public
as $$
declare
  r public.reviews;
begin
  select * into r from public.reviews where id = p_review_id;
  if r.id is null then raise exception 'not_found'; end if;
  if not public.owns_approved_studio(r.studio_id) then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(trim(p_reply)) = 0 then raise exception 'Write a reply first.'; end if;
  update public.reviews set studio_reply = trim(p_reply), studio_replied_at = now() where id = r.id returning * into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Payouts
-- ---------------------------------------------------------------------------
create or replace function public.on_payout_paid()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  owner uuid;
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    select owner_id into owner from public.studios where id = new.studio_id;
    perform public.notify(owner, 'payout_sent', 'Payout sent 💸', public.format_money(new.amount, new.currency) || ' is on its way to your bank.', null, null, new.studio_id);
  end if;
  return new;
end;
$$;
create trigger on_payout_paid after update of status on public.payouts
  for each row execute function public.on_payout_paid();

-- ---------------------------------------------------------------------------
-- Realtime: stream chat messages and notifications to the app.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.messages, public.notifications;

-- Called by edge functions when an automatic balance charge fails.
create or replace function public.notify_payment_problem(p_booking_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id;
  perform public.notify(b.artist_id, 'system', 'Payment problem',
    'We couldn''t charge the remaining ' || public.format_money((b.price ->> 'due_later')::int, b.price ->> 'currency')
    || ' for booking ' || b.reference || '. Please update your card or contact support.', b.id);
end;
$$;
revoke execute on function public.notify_payment_problem from public, anon, authenticated;
