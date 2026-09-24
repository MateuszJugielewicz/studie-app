# SONORA

En markedsplads, hvor artister finder og booker lydstudier, og betaler direkte i appen.

```
Studie ansøger → Admin godkender → Synligt på platformen → Artister finder → Booker → Betaler
```

| Del | Mappe | Teknologi |
| --- | --- | --- |
| iOS-app (artister + studier) | `ios/` | SwiftUI, iOS 17+, MapKit, Stripe PaymentSheet, Supabase |
| Backend | `supabase/` | Postgres + Row Level Security, Auth (e-mail/Apple/Google), Storage, Realtime, Edge Functions, pg_cron |
| Admin-dashboard (web) | `admin/` | React + TypeScript + Vite |

Både appen og admin-dashboardet kører i **demo-mode** med indbygget testdata, når der ikke er sat nøgler op. Så kan du prøve alt med det samme.

---

## Kom i gang

### iOS-appen (demo-mode)

Kræver Xcode 16 eller nyere. Projektfilen ligger i repoet:

```bash
open ios/Sonora.xcodeproj
```

Ændrer du `ios/project.yml`, så generér projektet igen med [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate` i `ios/`).

Kør på en simulator. Log ind med en demo-konto:

- Artist: `artist@demo.sonora` / `demo1234`
- Studie: `studio@demo.sonora` / `demo1234`

Opretter du en ny studiekonto, kan du i demo-mode trykke **"Simulate approval"** i stedet for at vente på en admin.

### Admin-dashboardet

```bash
cd admin
npm install
npm run dev            # http://localhost:5173 (demo-data, bare tryk "Sign in")
```

---

## Features

### 🎤 Artist
- Opret konto / login med e-mail, **Sign in with Apple** og **Google**
- Artistprofil: billede, artistnavn, genrer, by, bio, links (Spotify, Apple Music, Instagram, TikTok, YouTube, SoundCloud, hjemmeside), badge for verificeret artist
- Indstillinger: notifikationer per type, standard-søgeradius, km/miles, slet konto
- **Find studier:** fritekstsøgning, liste- og kortvisning (MapKit), område-oversigt ("📍 Athens · 12 studios within 5 km · From €15/hour")
- **Filtre:** pris, afstand, genrer, faciliteter, udstyr (fx "U87"), ledig på en bestemt dag, rating, instant book, engineer/mix/mastering
- **Sortering:** tættest, billigst, bedst anmeldt, mest populære
- **Studieprofil:** billeder, video, beskrivelse, område, priser per sessionstype, tilvalg (mix, mastering, producer, engineer), faciliteter, udstyr og mikrofoner, engineers/producere, kapacitet, genrer, åbningstider, regler, afbestillingsregler, anmeldelser og rating, næste ledige tider, kort, rutevejledning (Apple Maps / Google Maps), chat
- **Booking:** vælg sessionstype, antal timer, dato, ledigt tidspunkt, tilvalg og note → se samlet pris → betal → bekræftelse (+ tilføj til kalender)
- Bookingoversigt med kommende, **kalender** og historik; aflys (med refundering efter studiets politik), ændr tidspunkt, kvitteringer, anmeld problem

### 💳 Betaling
- Kort og **Apple Pay** via Stripe PaymentSheet (Google Pay tilbydes af samme løsning på Android)
- **Kontant betaling i studiet**, hvis studiet tillader det (ikke muligt, når studiet kræver depositum)
- **Instant book:** betaling trækkes med det samme. **Request to book:** kortet reserveres og trækkes først, når studiet accepterer
- **Depositum**, hvis studiet kræver det; restbeløbet trækkes automatisk efter sessionen
- **Platform fee: 10 % af alt salg.** Artisten betaler studiets pris uden ekstra gebyr.
  - **Kort:** Sonora modtager betalingen og udbetaler 90 % til studiet.
  - **Kontant:** studiet modtager hele beløbet. De 10 % bogføres som gæld i studiets gebyr-regnskab (`studio_fee_ledger`), når sessionen er gennemført. Gælden modregnes automatisk i studiets næste kort-udbetalinger. Resten kan admin fakturere via Stripe (14 dages betaling), registrere som betalt eller eftergive.
- Betalingsstatus, kvitteringer, automatiske refunderinger efter afbestillingspolitik (fleksibel / moderat / streng)
- **Studieudbetaling** via Stripe Connect, 2 dage efter gennemført session

### 🎛️ Studie
- Studieejer opretter konto og udfylder ansøgning: navn, billeder/video, adresse (+ placering på kort), kontakt, beskrivelse, priser og sessionstyper, åbningstider, udstyr, faciliteter, genrer, regler, bookingbetingelser, udbetalingsoplysninger
- Ansøgningsstatus med beskeder fra admin ("changes requested")
- **Dashboard:** kommende bookinger, anmodninger (accepter/afvis), indtjening denne måned, kommende udbetalinger, rating
- **Kalender** med bookinger og **blokering af tider**
- Tidligere bookinger, indtjening med graf, udbetalinger
- Administrer priser, åbningstider og profil; slå studiet live/på pause
- Svar på anmeldelser og rapportér falske anmeldelser

### 💬 Kommunikation
- Chat mellem artist og studie, **altid knyttet til et studie eller en booking** (ingen fri social messaging mellem artister)
- Systembeskeder i chatten ved aflysning/ændring
- Push-notifikationer (APNs) + indbakke i appen
- Påmindelser 24 timer og 2 timer før sessionen
- Artist får besked om: booking bekræftet/ændret/aflyst/afvist, påmindelse, ny besked, refundering, "skriv en anmeldelse"
- Studie får besked om: ny booking/anmodning, ny besked, aflysning, udbetaling, godkendt/afvist, ny anmeldelse

### ⭐ Anmeldelser
- Kun efter en gennemført booking, én per booking
- 1–5 stjerner samlet + faciliteter + studieoplevelse + engineer/producer (valgfrit) + tekst
- Studiet kan svare offentligt og rapportere anmeldelser

### 🛠️ Admin-dashboard
- **Oversigt/statistik:** antal artister og studier, bookinger, bookingrate, omsætning, platformens indtjening, mest populære studier og områder, bookinger per dag
- **Studier:** nye ansøgninger, godkendte, afviste, "changes requested", suspenderede. Gennemgå alle oplysninger, godkend, afvis, anmod om ændringer, verificér, markér aktiv/inaktiv, suspendér, redigér, historik
- **Brugere:** artister og studier, verificér, suspendér, ban, genaktivér
- **Bookinger:** alle, aktive, gennemførte, aflyste, refunderinger, problemer/tvister (løs tvist, refundér helt eller delvist)
- **Betalinger:** transaktioner, platform fees, studieudbetalinger, refunderinger, fejlede betalinger
- **Moderation:** rapporterede brugere, anmeldelser, studier og chatbeskeder (skjul anmeldelse, suspendér bruger/studie, afvis rapport)

---

## 🔐 Sikkerhed & juridisk

| Krav | Hvor |
| --- | --- |
| Terms & Conditions | `legal/terms.md` |
| Privacy Policy (GDPR) | `legal/privacy.md` |
| Cookie policy | `legal/cookies.md` (appen bruger ingen cookies/tracking) |
| Refund & Cancellation policy | `legal/refund-and-cancellation.md` |
| Studieaftale (10 % fee, kontant, udbetaling) | `legal/studio-agreement.md` |
| Community guidelines / rapportering | `legal/community-guidelines.md` |
| Accept af vilkår | Ved oprettelse + blokerende skærm ved nye versioner. Version og tidspunkt gemmes (`profiles.accepted_terms_*`) |
| Konto-sletning | Indstillinger → Slet konto (`delete-account`): aflyser med refundering, anonymiserer ved bogføringspligt |
| Dataeksport (GDPR art. 15/20) | Indstillinger → Download my data (`export-data`) → JSON-fil |
| Rapportering | Rapportér studie, anmeldelse, besked, artist/studie fra booking → admin-moderation |
| Payment provider | Stripe (PCI-DSS); kortdata rører aldrig Sonoras servere |
| Sikker login | Adgangskode ≥ 10 tegn med store/små bogstaver og tal, e-mailbekræftelse, rate limits, token-rotation, Keychain på iOS. **Admins skal bruge 2-faktor (TOTP)** – håndhæves i databasen (`is_admin()` kræver `aal2`), i edge functions og i admin-dashboardet |

Dokumenterne vises i appen (Indstillinger → Legal) og er **udkast med pladsholdere** (`[COMPANY NAME]` osv.). De skal gennemgås af en advokat før lancering.

### Rollebaserede rettigheder

| | Artist | Studie (ikke godkendt) | Studie (godkendt) | Admin (med 2FA) |
| --- | :-: | :-: | :-: | :-: |
| Søge og booke studier | ✅ | – | – | – |
| Oprette/redigere studie-ansøgning | ❌ | ✅ | ✅ | ✅ |
| Synlig for artister | – | ❌ | ✅ | – |
| Kalender, blokering af tider | – | ❌ | ✅ | – |
| Acceptere/afvise/aflyse bookinger | – | ❌ | ✅ | – |
| Chatte som studie, svare på anmeldelser | – | ❌ | ✅ | – |
| Udbetalinger | – | opsætning | ✅ | – |
| Godkende studier, moderere, refundere | ❌ | ❌ | ❌ | ✅ |

**En artist kan aldrig oprette et studie.** Databasen afviser det (`guard_studios`), og studie-funktioner kræver et admin-godkendt studie (`owns_approved_studio()`). Det gælder både i RLS-politikker, RPC'er, edge functions og appen. Studiekonti er separate fra artistkonti.

## Sikkerhed og dataregler

Reglerne ligger i databasen, så de gælder uanset hvilken klient der kalder:

- **Row Level Security** på alle tabeller: artister ser kun egne bookinger, studier kun deres egne, og kun godkendte og aktive studier er offentlige
- Triggers forhindrer, at brugere ændrer moderationsfelter: et studie kan ikke godkende sig selv, og en bruger kan ikke gøre sig selv til admin eller verificeret
- **Dobbeltbooking er umulig**, fordi en exclusion constraint i Postgres afviser overlappende bookinger
- Priser beregnes på serveren (`supabase/functions/_shared/pricing.ts`); klienten viser kun et estimat
- Alt der flytter penge sker i Edge Functions med Stripe (idempotente kald + webhook)

---

## Produktion: opsætning

### 1. Supabase
```bash
supabase link --project-ref <ref>
supabase db push                      # kører migrationerne i supabase/migrations
supabase functions deploy             # alle edge functions
supabase secrets set --env-file supabase/functions/.env   # se .env.example
```
Kør én gang i SQL-editoren, så cron-jobs og push kan kalde edge functions:
```sql
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<service-role-key>', 'service_role_key');
```
Opret den første admin: opret en konto og kør `update profiles set role = 'admin' where email = 'dig@firma.dk';`. Ved første login i admin-dashboardet sætter du 2-faktor op med en authenticator-app.

Slå **Apple** og **Google** til under Auth → Providers, og tilføj `sonora://auth-callback` som redirect URL.

### 2. Stripe
- Slå **Connect** (Express) til, så studier kan få udbetalinger
- Opret en webhook til `https://<ref>.supabase.co/functions/v1/stripe-webhook` med events:
  `payment_intent.succeeded`, `payment_intent.amount_capturable_updated`, `payment_intent.payment_failed`, `charge.refunded`, `account.updated`, `invoice.paid`
- Apple Pay: opret merchant ID `merchant.com.sonora.app` og upload Stripes certifikat

### 3. iOS
Kopiér `ios/Config/Secrets.example.xcconfig` til `ios/Config/Secrets.xcconfig` og udfyld Supabase-URL, anon key og Stripe publishable key. Så bruger appen den rigtige backend. Push kræver en APNs-nøgle (`APNS_*` secrets).

### 4. Admin
```bash
cd admin && cp .env.example .env   # udfyld VITE_SUPABASE_URL og VITE_SUPABASE_ANON_KEY
npm run build                      # deploy dist/ til fx Vercel, Netlify eller Cloudflare Pages
```

---

## Tests

| Hvad | Kommando |
| --- | --- |
| iOS unit tests (pris, refundering, tilgængelighed, søgning, bookingflow) | `xcodebuild test` (kører i CI på macOS) |
| Database: migrationer, RLS, triggers, dobbeltbooking, admin-statistik | `cd supabase/tests && npm install && npm test` |
| Edge functions: typecheck + pris/tidszone-tests | `cd supabase/functions && deno check */index.ts && deno test _shared/` |
| Admin: typecheck + build | `cd admin && npm run build` |

Alle fire kører automatisk i GitHub Actions (`.github/workflows/ci.yml`).

## Struktur

```
ios/
  project.yml                XcodeGen-projekt
  Sonora/App                 app-entry, global state, konfiguration
  Sonora/Models              datamodeller (matcher databasen)
  Sonora/Core                pris, tilgængelighed, søgning, indtjening (ren logik, testet)
  Sonora/Services            Backend-protokol, SupabaseBackend, MockBackend (demo), Stripe, lokation, push
  Sonora/Features            Auth, Artist, Discover, StudioDetail, Booking, Chat, Reviews, StudioOwner
supabase/
  migrations/                skema, sikkerhed, app-logik, admin, cron
  functions/                 create-booking, create-payment-intent, confirm-payment, stripe-webhook,
                             cancel-booking, reschedule-booking, respond-booking, process-payouts,
                             payout-account, send-push, delete-account, admin-refund,
                             confirm-cash-booking, studio-fee-invoice, export-data
  tests/                     database-tests (PGlite)
admin/                       React admin-dashboard
legal/                       vilkår, privatliv, cookies, refundering, studieaftale (vises i appen)
```
