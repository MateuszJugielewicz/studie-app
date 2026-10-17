-- EasySesh: people can browse approved studios and their reviews before signing up (App Store
-- guideline 5.1.1(v)). Booking, messaging and everything else still needs an account.

-- The signed-in policy also looks at bookings, which guests can't read, so it only applies to
-- signed-in users and guests get their own, simpler policy.
alter policy "studios: read public" on public.studios to authenticated;
drop policy if exists "studios: guests read approved" on public.studios;
create policy "studios: guests read approved" on public.studios for select to anon
  using (status = 'approved' and is_active);

drop policy if exists "reviews: guests read" on public.reviews;
create policy "reviews: guests read" on public.reviews for select to anon
  using (not is_hidden and exists (select 1 from public.studios s where s.id = reviews.studio_id and s.status = 'approved' and s.is_active));

grant select on public.studios, public.reviews to anon;
grant execute on function public.studio_busy_intervals(uuid[], timestamptz, timestamptz) to anon;
