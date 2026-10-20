# EasySesh – App Store release checklist

Checked against Apple's App Review Guidelines (developer.apple.com/app-store/review/guidelines),
the account-deletion rules (developer.apple.com/support/offering-account-deletion-in-your-app),
the privacy-manifest rules and the screenshot specifications.

## Already fixed in the code

| Apple rule | What could get the app rejected | Fix |
|---|---|---|
| 1.2 User-generated content | No way to block abusive users | Block / unblock from the chat (⋯ menu), artist profiles and studio pages; list under Settings → Blocked accounts. Blocked people can't message each other (enforced in the database). |
| 1.2 | Terms didn't say "zero tolerance for objectionable content" | Added to Terms §10 and Community Guidelines in all 10 languages. |
| 3.1.3(g) Buying "boosts" | Studios paid for promotions with Stripe inside the app | The app only shows promotion status. Promotions are bought on the website (easysesh.live) or granted by admins; the app neither sells nor links to them. |
| 5.1.1(v) Login | The app required an account just to look at studios | "Look around first" on the start screen: guests can browse studios, prices and reviews. Booking, messaging and reporting ask them to sign up. |
| 5.1.1(v) Account deletion | Sign in with Apple tokens weren't revoked; posted content stayed | Deleting an account asks Apple for a fresh code and revokes the token on the server; review texts and messages are removed, ratings stay anonymous. |
| 5.1.1(i) Privacy policy | Links pointed to easysesh.app (not your domain) | Public pages served by the `legal` edge function (see URLs below). |
| Privacy manifest (required since May 2024) | No `PrivacyInfo.xcprivacy` | Added (UserDefaults reason CA92.1, no tracking, collected data listed). |
| Export compliance | Missing `ITSAppUsesNonExemptEncryption` | Set to NO (the app only uses standard HTTPS). |
| 2.5.4 Background modes | Declared "remote-notification" background mode without using it | Removed (push notifications still work). Unused camera permission text removed. |

## You must do these before submitting

1. **Company details in the legal texts.** `legal/*.md` (all languages) still contain `[COMPANY NAME]`,
   `[ADDRESS]`, `[CVR/VAT NO.]`, `[COUNTRY]`, `[CITY]`,
   `[REGION]`, `[PROVIDER]`. A reviewer seeing placeholders can reject the app (2.1, 5.1.1). Send these
   details to Claude and it fills them in everywhere, or replace them yourself in `legal/` (the
   website and the apps read it directly).
2. **Support email.** Set `EASYSESH_SUPPORT_EMAIL` in `ios/Config/App.xcconfig` and the Supabase secret
   `SUPPORT_EMAIL` (shown on the public support page). Must be an address you actually read.
3. **Live Stripe keys.** In `ios/Config/App.xcconfig` replace the `pk_test_…` key with your `pk_live_…`
   key, and set the live `STRIPE_SECRET_KEY` + live webhook secrets in Supabase. Make the two webhooks
   again in live mode (same URL, same events).
4. **Supabase.** Run `supabase/updates/latest.sql` in the SQL Editor and deploy all functions
   (`.\supabase.exe functions deploy --project-ref gdebbieifsvspszmevwa --no-verify-jwt`).
5. **Apple Developer account (paid, 99 USD/year)** → Certificates, Identifiers & Profiles:
   - App ID `com.easysesh.app` with **Sign in with Apple**, **Push Notifications** and **Apple Pay**.
   - Apple Pay merchant ID `merchant.com.easysesh.app` (and upload Stripe's Apple Pay certificate:
     Stripe Dashboard → Settings → Payment methods → Apple Pay).
   - A **Key** with *Apple Push Notifications service* and *Sign in with Apple*. Download the .p8 and set
     Supabase secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_PRODUCTION=true` (push) and `APPLE_TEAM_ID`,
     `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (token revocation when accounts are deleted).
6. **Demo accounts for App Review** (guideline 2.1 – reviewers must be able to sign in):
   - In the app, sign up an artist: e.g. `review.artist@<your domain>` and confirm the email.
   - Sign up a studio owner: e.g. `review.studio@<your domain>`, fill in the studio and submit it.
   - Approve that studio in the admin panel, and connect payouts with Stripe's test data.
   - Make sure at least a few real or demo studios are approved, and mention a city to search in the
     review notes – reviewers are often in the US, far from your studios.
7. **Build:** in Xcode select *Any iOS Device*, Product → Archive, then Distribute App → App Store
   Connect. Bump `CURRENT_PROJECT_VERSION` in `ios/project.yml` (or in Xcode) for every new upload.

## App Store Connect

- **Privacy Policy URL:** `https://easysesh.live/legal/privacy`
- **Support URL:** `https://gdebbieifsvspszmevwa.supabase.co/functions/v1/legal/support`
- **Terms (EULA)**: add `…/functions/v1/legal/terms` to the description, or under App Information → License Agreement.
- **Category:** Music (secondary: Business).
- **Age rating:** answer *Yes* to user-generated content / messaging between users. Unrestricted web
  access: No. Gambling, violence, etc.: No.
- **App Privacy** (must match `ios/EasySesh/Resources/PrivacyInfo.xcprivacy`) – data **linked to the
  user**, used for **App Functionality** only, **not used for tracking**: Name, Email, Phone number,
  Physical address (studios), User ID, Photos, Emails or text messages (chat), Other user content
  (reviews, bios), Customer support, Purchase history, Payment info (handled by Stripe), Other financial
  info (studio payouts), Device ID (push token). Location: not collected (used on the device only).
- **Screenshots:** at least 1 (up to 10) for the iPhone *Dynamic Island* display – 1206 × 2622 or
  1179 × 2556 px, PNG/JPEG without transparency. Take them on the iPhone 16/17 Pro simulator
  (⌘S in the Simulator).
- **Price:** Free. No in-app purchases.

## Review notes (paste into "Notes" under App Review Information)

```
EasySesh is a marketplace for booking recording studio sessions.

Guest access: tap "Look around first" on the start screen to browse studios without an account.
Search for "<CITY WITH STUDIOS>" if no studios are near you.

Demo accounts:
- Artist: review.artist@<domain> / <password>
- Studio owner (approved studio): review.studio@<domain> / <password>

Payments: studio sessions are real-world services used outside the app, so they are paid with
Stripe / Apple Pay (guideline 3.1.3(e)). Test card in this build: 4242 4242 4242 4242, any future
date, any CVC. The app sells no digital content and has no in-app purchases; studio and artist promotions are
bought outside the app (on the website) and the app only shows their status.

User-generated content (guideline 1.2): users can report studios, users, reviews and messages,
and block other users (⋯ menu in a chat or on a profile; Settings → Blocked accounts). Reports
are reviewed by our moderation team within 24 hours; we can warn, suspend or ban accounts. The
terms state zero tolerance for objectionable content.

Account deletion: Settings → Delete account.
```
