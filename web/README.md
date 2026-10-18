# EasySesh – website

The website version of the app: guests can browse studios, artists can book and pay, chat and
manage their sessions, and studio owners can run their studio (dashboard, calendar, requests,
editor, payouts, promotion) – all from a browser. It uses the same Supabase project, the same
translations (`ios/EasySesh/Localizable.xcstrings`) and the same legal texts (`legal/`) as the
iOS and Android apps, so an account works everywhere.

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

Open <http://localhost:5173>.

## Put it online

1. Build the site:
   ```powershell
   cd studie-app\web
   npm run build
   ```
   The finished website is the `web\dist` folder.
2. Easiest host: <https://app.netlify.com/drop> – drag the `dist` folder onto the page. You get a
   link like `https://easysesh-123.netlify.app` (you can connect your own domain later under
   *Domain management*). Cloudflare Pages and Vercel work too; the files `public/_redirects` and
   `vercel.json` make page links like `/studios/…` work on those hosts.

## After the site has an address (do once)

Replace `https://YOUR-SITE` with the real address.

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
- Admins see a short note pointing to the admin dashboard (`admin/`).

## Commands

| Command | What it does |
| --- | --- |
| `npm run dev` | Local site with live reload |
| `npm run build` | Type-check and build into `dist/` |
| `npm run typecheck` | Type-check only |
| `npm run l10n` | Rebuild translations from `Localizable.xcstrings` (runs automatically) |
