# EasySesh – open items before launch

Things only the owner can do. Details and steps are in `docs/APP_STORE_RELEASE.md`
(iOS) and `android/README.md` (Android).

## Legal / company
- [ ] Company name, address, CVR/VAT number, support email, privacy email, governing-law country
      and city. They replace the `[PLACEHOLDER]`s in `legal/*.md` (all 10 languages). Send them to
      Claude to fill in everywhere, then run `python3 supabase/scripts/build_legal_function.py`.
- [ ] Email provider and Supabase region for the privacy policy (`[PROVIDER]`, `[REGION]`).
- [ ] Have a lawyer review the terms and privacy policy (they are marked as drafts).
- [ ] A support email you actually read: `EASYSESH_SUPPORT_EMAIL` (iOS `ios/Config/App.xcconfig`),
      `supportEmail` (Android `android/local.properties`) and the Supabase secret `SUPPORT_EMAIL`.

## Payments (Stripe)
- [ ] Live keys: `pk_live_…` in the apps, `sk_live_…` as the Supabase secret `STRIPE_SECRET_KEY`.
- [ ] Recreate both webhooks in live mode (same URL and events) and set the live signing secrets
      (`STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`).
- [ ] Roll the test keys that were pasted in chat (Stripe → Developers → API keys → Roll).
- [ ] Rotate the Supabase service_role key that was pasted in chat (Project Settings → JWT Keys),
      then update the vault secret `service_role_key`.

## Apple (iOS)
- [ ] Paid Apple Developer account.
- [ ] App ID `com.easysesh.app` with Sign in with Apple, Push Notifications, Apple Pay.
- [ ] Apple Pay merchant ID `merchant.com.easysesh.app` + Stripe's Apple Pay certificate.
- [ ] APNs / Sign in with Apple key (.p8) → Supabase secrets `APNS_KEY_ID`, `APNS_TEAM_ID`,
      `APNS_PRIVATE_KEY`, `APNS_PRODUCTION=true`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`.
- [ ] App Store Connect: privacy policy + support URL, App Privacy answers, age rating, screenshots
      (1206 × 2622), review notes (template in `docs/APP_STORE_RELEASE.md`).

## Google (Android)
- [ ] Google Play Console account (25 USD once).
- [ ] Firebase project for push notifications → values in `android/local.properties` and the
      Supabase secrets `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`, then redeploy `send-push`.
- [ ] Google sign-in: OAuth client IDs (Web + Android with the app's SHA-1) in Google Cloud, and the
      Web client ID in Supabase → Authentication → Providers → Google.
- [ ] Release signing key (keystore) – keep it safe, Play needs the same key for every update.
- [ ] Play Console: privacy policy URL, Data safety form, content rating, screenshots, test account.
- [ ] Test the Android app on a real phone (sign-in, booking + Google Pay, chat, push, payouts) –
      it was only built and checked with on-computer screenshots so far.

## Review accounts (both stores)
- [ ] Artist demo account and studio-owner demo account with an approved studio.
- [ ] A few approved studios, and a city to search for in the review notes.

## Supabase
- [ ] Run `supabase/updates/latest.sql` after each update and redeploy the functions.
