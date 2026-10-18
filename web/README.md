# EasySesh – website

The website version of the app: guests can browse studios, artists can book and pay, chat and
manage their sessions, and studio owners can run their studio (dashboard, calendar, requests,
editor, payouts, promotion) – all from a browser. It uses the same Supabase project, the same
translations (`ios/EasySesh/Localizable.xcstrings`) and the same legal texts (`legal/`) as the
iOS and Android apps, so an account works everywhere.

It also includes the **admin dashboard**: https://admin.easysesh.live on the live site, `/admin`
locally and on `*.pages.dev` previews (studio approvals, users, bookings, payments,
promotions, moderation, support and the changelog/"What's new"). Admins sign in on the website as
usual and are taken there; two-factor authentication (an authenticator app) is required. Everything
done there applies to the iOS app, the Android app and the website alike, because they all use the
same backend.

The public keys (Supabase URL + anon key, Stripe **publishable** key, support email) are read from
`ios/Config/App.xcconfig` when building, so nothing needs to be filled in. To override one, copy
`.env.example` to `.env.local`.

## Run it on your PC (Windows, PowerShell)

Install Node.js 20 or newer from <https://nodejs.org> (the "LTS" button), then:

```powershell
cd studie-app\web
npm install
npm run dev
```

Open <http://localhost:5173> (the admin dashboard is <http://localhost:5173/admin>).

## Put it online

1. Build the site:
   ```powershell
   cd studie-app\web
   npm run build
   ```
   The finished website is the `web\dist` folder.
2. **Cloudflare Pages** (the live site, https://easysesh.live):
   - <https://dash.cloudflare.com> → **Workers & Pages** → **Create** → **Pages** tab →
     **Upload assets** → project name `easysesh` → **Create project** → drag the `dist` folder in →
     **Deploy site**.
   - In the project → **Custom domains** → **Set up a custom domain** → `easysesh.live` →
     **Activate domain**. Repeat for `www.easysesh.live` if you want it.
   - To update the site later: project → **Create deployment** → drag the new `dist` folder, or
     from PowerShell with a Cloudflare API token (Pages: Edit):
     ```powershell
     $env:CLOUDFLARE_API_TOKEN="<token>"; npx wrangler pages deploy dist --project-name easysesh --branch main
     ```

   **Live now:** the Pages project `easysesh` serves https://easysesh.live,
   https://www.easysesh.live and https://admin.easysesh.live (proxied CNAME records to
   `easysesh.pages.dev`). The same files serve all three: `src/boot.ts` opens the admin dashboard
   on `admin.` and the website everywhere else (`src/lib/hosts.ts`).

   Netlify Drop (<https://app.netlify.com/drop>) and Vercel work too; `public/_redirects` and
   `vercel.json` make page links like `/studios/…` work there.

## After the site has an address (do once)

Replace `https://YOUR-SITE` with the real address (`https://easysesh.live`).

1. **Supabase → Authentication → URL Configuration**
   - *Redirect URLs* → **Add URL**: `https://YOUR-SITE/auth/callback`
   - Leave *Site URL* as it is unless the website should be the main place e-mail links open.
2. **Stripe payouts return to the website** – in PowerShell, in the folder with `supabase.exe`:
   ```powershell
   .\supabase.exe secrets set --project-ref gdebbieifsvspszmevwa SITE_URL=https://YOUR-SITE
   .\supabase.exe functions deploy payout-account payout-return --project-ref gdebbieifsvspszmevwa --no-verify-jwt
   ```
   (Run the deploy from the `studie-app` folder.)
3. **Sign in with Google** – Google Cloud Console → *APIs & Services → Credentials* → your Web
   client → add `https://YOUR-SITE` under *Authorized JavaScript origins*.
4. **Sign in with Apple** – Apple Developer → *Identifiers → Services IDs* → your Services ID →
   add your domain under *Domains and Subdomains*.
5. **Apple Pay / Google Pay on the website** – Stripe Dashboard → *Settings → Payment method
   domains* → **Add a new domain** → your site's domain. Cards work without this.

## What's different from the apps

- No push notifications (the Inbox and unread badges still update live while the site is open).
- No intro carousel or studio tour, no haptics.
- Location comes from the browser (it asks for permission); maps use OpenStreetMap.

## Commands

| Command | What it does |
| --- | --- |
| `npm run dev` | Local site with live reload |
| `npm run build` | Type-check and build into `dist/` |
| `npm run typecheck` | Type-check only |
| `npm run l10n` | Rebuild translations from `Localizable.xcstrings` (runs automatically) |
