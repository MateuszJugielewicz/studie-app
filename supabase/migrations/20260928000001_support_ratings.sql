-- EasySesh: users rate how their support request was handled once it's closed.

alter table public.support_tickets
  add column if not exists rating smallint check (rating between 1 and 5),
  add column if not exists rating_comment text,
  add column if not exists rated_at timestamptz;

-- The ticket owner rates a closed ticket (can change it later).
create or replace function public.rate_support_ticket(p_ticket_id uuid, p_rating integer, p_comment text default null)
returns public.support_tickets
language plpgsql security definer set search_path = public
as $$
declare
  v_status text := (select t.status from public.support_tickets t where t.id = p_ticket_id and t.user_id = auth.uid());
begin
  if v_status is null then raise exception 'not_found'; end if;
  if v_status <> 'closed' then raise exception 'You can rate a request once it is closed.'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Pick 1 to 5 stars.'; end if;
  update public.support_tickets
  set rating = p_rating,
      rating_comment = nullif(left(btrim(coalesce(p_comment, '')), 1000), ''),
      rated_at = now()
  where id = p_ticket_id;
  return (select t from public.support_tickets t where t.id = p_ticket_id);
end;
$$;

-- Admin view keeps its columns in sync with the table (t.* is expanded when the view is created).
drop view if exists public.admin_support_tickets;
create view public.admin_support_tickets with (security_invoker = true) as
select t.*, p.email as user_email, p.role as user_role,
  coalesce(nullif(a.artist_name, ''), nullif(s.name, ''), p.email) as user_name,
  b.reference as booking_reference
from public.support_tickets t
join public.profiles p on p.id = t.user_id
left join public.artist_profiles a on a.id = t.user_id
left join public.studios s on s.owner_id = t.user_id
left join public.bookings b on b.id = t.booking_id;
