# Payments: every method, and the keys you add later

All online payments go through Stripe. The checkout everywhere (website, iPhone app, Android app) is
Stripe's own payment form, which shows **every method you turn on in the Stripe dashboard** that works
for the amount, currency and the payer's country. Nothing needs changing in the code to add a method.

| Where | Methods shown |
|---|---|
| Website | Cards, Apple Pay (Safari), Google Pay (Chrome), Link, PayPal, Klarna, MobilePay, iDEAL, Bancontact, BLIK, EPS, Revolut Pay, … |
| iPhone app | Cards, Apple Pay, and the same list (bank-app methods return to the app via `easysesh://stripe-redirect`) |
| Android app | Cards, Google Pay, and the same list |

Bookings and receipts show which method was used (Apple Pay, Klarna, …).

Methods that only settle days later (SEPA Direct Debit, bank transfers, Multibanco, …) don't work for
bookings: a session must be confirmed right away. The apps hide them automatically; **keep them
switched off in the Stripe dashboard** so the website doesn't show them either. Request-to-book studios
authorise the payment and capture it when they accept, so for those only methods that support that
(cards, wallets, Klarna, PayPal, …) are offered. Stripe filters this by itself.

## 1. Stripe (do first)

1. Stripe Dashboard → **Settings → Payment methods**: turn on the methods you want (cards, Apple Pay,
   Google Pay and Link are on by default). Leave the "delayed" ones above off.
2. Switch to live mode: put the `pk_live_…` key in `ios/Config/App.xcconfig`
   (`EASYSESH_STRIPE_PUBLISHABLE_KEY`, the Android app and the website read it from there too) and set the
   Supabase secrets `STRIPE_SECRET_KEY` (`sk_live_…`), `STRIPE_WEBHOOK_SECRET` and
   `STRIPE_CONNECT_WEBHOOK_SECRET` from the live webhooks (same URL and events as in test mode).
3. Admin panel → **Payments → Register website** (owner only). This registers easysesh.live and
   www.easysesh.live with Stripe so Apple Pay, Google Pay, Link and PayPal appear on the website. The
   Apple Pay verification file is already served at
   `https://easysesh.live/.well-known/apple-developer-merchantid-domain-association`. Run it again after
   switching to live keys (test and live mode have separate lists).
4. If the Stripe account isn't Greek, change `EASYSESH_MERCHANT_COUNTRY = GR` in
   `ios/Config/App.xcconfig` (used by both apps for Apple Pay / Google Pay).

## 2. Apple Pay in the iPhone app (needs the Apple Developer account)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers → Merchant IDs** → add
   `merchant.com.easysesh.app` (the ID in `EASYSESH_APPLE_PAY_MERCHANT_ID`).
2. Stripe Dashboard → Settings → Payment methods → **Apple Pay → iOS certificates → Add new
   application**: download Stripe's CSR, upload it to the merchant ID in Apple's portal (Create
   Certificate), and upload the resulting `.cer` back to Stripe.
3. On the App ID `com.easysesh.app`, enable the **Apple Pay Payment Processing** capability and select
   the merchant ID. The app's entitlements already list it.
4. Until this is done you can set `EASYSESH_APPLE_PAY_ENABLED = NO` in `App.xcconfig`; cards and the
   other methods still work.

## 3. Google Pay in the Android app (needs the Google Play developer account)

1. Test mode works straight away (Google shows test cards).
2. For live payments: sign in to the **Google Pay & Wallet Console** (pay.google.com/business/console)
   with the same Google account, fill in the business profile and accept the Google Pay API terms.
   Stripe is the payment processor, so you don't need a gateway merchant ID or to send Google an APK.
3. The app switches Google Pay to production by itself when the Stripe key is a `pk_live_…` key. To hide
   Google Pay until the console is set up, add `googlePayEnabled=false` to `android/local.properties`.

## 4. Check

Website: open a studio in Safari (Apple Pay) and Chrome (Google Pay) and start a booking. The Apple
Pay / Google Pay buttons show only on devices with a card in the wallet. Apps: book with a test card
first, then with Apple Pay / Google Pay.
