# EasySesh – Google Play release checklist

Checked against the Google Play Developer Program Policies (support.google.com/googleplay/android-developer/topic/9858052),
the target API level, 16 KB page size, account deletion, Data safety and payments rules.

## Already in order in the app

| Play rule | Status |
|---|---|
| Target API level | `targetSdk = 36` (Play asks for 35+ for new apps and updates). |
| 16 KB memory pages (required since Nov 2025 for apps targeting Android 15+) | Checked: the only native libraries in the build (from AndroidX) are 16 KB aligned. Re-check if a library with native code is added. |
| Payments policy | Studio sessions are real-world services, so Stripe (cards, Google Pay, Klarna, PayPal, …) is allowed instead of Google Play Billing. Promotions are a digital service, so the app doesn't sell them and doesn't link or point to where they're sold. Keep it that way in the store listing too. |
| User-generated content | Report studios, users, reviews and messages; block users; automatic flags for minors, off-platform payments and illegal content; a moderation team that can warn, suspend and ban; zero-tolerance terms. |
| Account deletion | In the app (Settings → Delete account) **and** on the web (sign in at https://easysesh.live → Settings → Delete account). Play asks for that web link. |
| Permissions | Only location (nearby studios, check-in), notifications (asked at runtime on Android 13+) and internet. Photos are picked with the system photo picker, so there's no photo/media permission to justify. No background location. |
| Edge-to-edge (enforced from Android 15) | Enabled (`enableEdgeToEdge()`). |
| Google Pay | `com.google.android.gms.wallet.api.enabled` is in the manifest; production mode turns on with the live Stripe key (`docs/PAYMENTS.md`). |
| Sign-in | Google (Credential Manager) and email. A demo account is needed for review (below). |

## You must do these in Play Console

1. **Developer account.** If it's a *personal* account, Google requires a **closed test with at least
   12 testers for 14 days in a row** before you can publish to production. Plan for that. An
   *organization* account (needs a D-U-N-S number) skips this.
2. **Signing and upload:** see `android/README.md` → Play Store (upload key, `bundleRelease`, raise
   `versionCode` each time).
3. **App content** (Policy → App content):
   - Privacy policy: `https://easysesh.live/legal/privacy`
   - **Ads:** No ads.
   - **App access:** give the review team the demo artist and studio accounts (same as for Apple, see
     `docs/APP_STORE_RELEASE.md` step 6) and say which city has studios.
   - **Target audience:** 18 and over only (the terms require 18+). Don't pick any under-18 group, or the
     Families policy applies.
   - **Content rating** (IARC questionnaire): users can interact and exchange messages, user-generated
     content: Yes; shares location with other users: No; digital purchases: No (sessions are real-world).
   - **Data safety:** data collected and shared only to run the app, encrypted in transit, users can ask for
     deletion. Collected: name, email, phone (studios), address (studios), user ID, approximate and
     precise location (check-in), photos, messages, other user content (reviews, bios), purchase
     history, payment info (processed by Stripe, a service provider), financial info (studio payouts),
     device ID (push token), app interactions for support tickets. Not used for ads or tracking. Delete
     account URL: `https://easysesh.live/settings`.
   - **Financial features:** declare that the app doesn't offer financial services (it only takes
     payments for its own bookings through Stripe).
   - **Government / health / news apps:** No.
4. **Google Pay:** set up the Google Pay & Wallet Console business profile (`docs/PAYMENTS.md` step 3).
5. **Store listing:** screenshots (phone, at least 2), feature graphic 1024 × 500, short and full
   description. Don't mention buying promotions on the website.
