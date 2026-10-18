-- Supabase security advisor: pin search_path on helper and trigger functions.
alter function public.before_review_insert() set search_path = public, extensions;
alter function public.booking_has_card_money(public.bookings) set search_path = public, extensions;
alter function public.distance_m(double precision, double precision, double precision, double precision) set search_path = public, extensions;
alter function public.format_money(integer, text) set search_path = public, extensions;
alter function public.guard_artist_profiles() set search_path = public, extensions;
alter function public.guard_notifications() set search_path = public, extensions;
alter function public.guard_profile_moderation() set search_path = public, extensions;
alter function public.guard_profiles() set search_path = public, extensions;
alter function public.guard_studio_extras() set search_path = public, extensions;
alter function public.guard_studio_moderation() set search_path = public, extensions;
alter function public.guard_studios() set search_path = public, extensions;
alter function public.is_trusted() set search_path = public, extensions;
alter function public.pct(integer, integer) set search_path = public, extensions;
alter function public.promotion_days(text) set search_path = public, extensions;
alter function public.promotion_price(text, text) set search_path = public, extensions;
alter function public.studio_validation_problems(public.studios) set search_path = public, extensions;
alter function public.touch_updated_at() set search_path = public, extensions;
