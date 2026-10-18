# Security review – 18 October 2026

Scope: the database (Supabase: row-level security, functions, storage), the edge functions, the
website + admin dashboard, the iOS app and the Android app. Anyone can call the API directly with
the public key that ships in the apps, so the review treats every client as untrusted.

The abuse tests live in `supabase/tests/attacks.sql` and run with `cd supabase/tests && npm test`
(43 attacks on a database with Supabase's production privileges, plus the 94 existing checks).

## Fixed

| # | Severity | Problem | Fix |
|---|----------|---------|-----|
| 1 | High | A studio owner could give an add-on a **negative price** after approval. Bookings with it got a negative total and a negative platform fee; for cash bookings the "fee" would be credited to the studio against its payouts. Zero session prices and out-of-range booking settings (e.g. deposit −50 %) were also accepted after approval. | `validate_studio_listing` trigger checks every save; `bookings_price_not_negative` constraint rejects any booking with a negative total, subtotal, fee, payout or amount due (migration `20261018000001`). |
| 2 | High | **Admin dashboard XSS**: studio photo and video links were rendered as raw links. A `javascript:` "video link" clicked by an admin reviewing the application could run in the admin's session. | Admin links only open `http(s)` URLs (`safeUrl`), in the website's admin and in `admin/`. |
| 3 | Medium | **Android sign-in links used the implicit flow**: email confirmation, password reset and Google/Apple links carried the whole session in the `easysesh://` link, which another app registering the same scheme could catch. | Android uses PKCE (like iOS and the website). Admin-sent reset emails (which come from the server) are still accepted. |
| 4 | Low | Scheduler functions (`run_booking_housekeeping`, `run_cash_housekeeping`, `queue_session_reminders`, `refresh_studio_rating`) could be called by anyone; `is_blocked_between` told anyone whether two users had blocked each other. | Execute revoked for users; pg_cron and internal functions still run them. |
| 5 | Low | Push tokens are placed in the URL of Apple's push API and weren't validated. | `device_tokens_token_format` constraint. |
| 6 | Low | A paid PaymentIntent was applied to its booking without checking it was the booking's own intent for the full amount. (Only the server can create intents, so not exploitable today.) | `applyPaymentIntent` checks intent id and amount. |
| 7 | Low | Sign-in `?next=` accepted any value (the browser blocked cross-site targets, but it relied on that). | Only same-site paths are followed. |
| 8 | Low | Website had no security headers. | `public/_headers`: no framing (clickjacking), nosniff, referrer policy, permissions policy, HSTS. |
| 9 | Bug | iOS password-reset links (PKCE) never asked for a new password. | Both apps remember that a reset was requested and ask on the next sign-in link. |

## Checked and fine

- Every table has row-level security; admin views run as the caller (`security_invoker`); every
  `security definer` function pins `search_path`.
- Users can't change protected columns: role, status, verification, ratings, badges, platform fee,
  promotion, suspension, studio approval/owner (guard triggers; tested).
- Admin functions require an admin with two-factor (`aal2`), in the database and the edge functions.
- Prices are always computed on the server from the studio listing; artists can't pick prices,
  statuses or payment states, can't mark cash as received, and can't confirm cash where the studio
  doesn't accept it.
- Bookings, messages, transactions, payouts, payout accounts, support tickets and profiles (emails)
  are only visible to the people involved; guests only see approved studios and visible reviews.
- Messages can't be sent as someone else, as "system", into others' chats or between people who
  blocked each other; notifications can't be created by users; reviews only after a completed session.
- Stripe webhook verifies signatures; refunds are capped at what was paid and idempotent; payouts
  run only with the service key; payout onboarding only for the studio's owner.
- Storage: users can only write in their own folder.
- No secret keys in the apps, the website or the git history. iOS has no ATS exceptions; Android
  has no cleartext traffic, backups are off and only the launcher activity is exported.
- User links (social links, studio website/video) always become `https://` links in all three apps.

## To do on the live system

1. Run `supabase/updates/latest.sql` in the SQL Editor (adds fixes 1, 4 and 5).
2. Redeploy the edge functions that use `_shared/stripe.ts` (fix 6):
   `create-payment-intent confirm-payment stripe-webhook respond-booking process-payouts`.
3. Ship new app builds (fixes 3 and 9).
4. Roll the keys that were pasted in chat (Stripe, Supabase service role, Cloudflare token).
