# Email – easysesh.live

| Address | Used for |
| --- | --- |
| support@easysesh.live | Support: shown in the apps, the website footer, the legal documents; replies to booking emails go here |
| easysesh@easysesh.live | General and privacy/data requests (legal documents, website footer) |
| mateusz@easysesh.live | Personal – not shown anywhere |
| noreply@easysesh.live | Sender of booking emails (and, optionally, sign-up / password emails) |

**Receiving** (all addresses) runs on iCloud+ Custom Email Domain. The iCloud records (MX, SPF,
DKIM `sig1._domainkey`, `apple-domain` TXT) are already in Cloudflare DNS.

**Sending from the server** can't use iCloud: Apple has no sending API for apps, iCloud's SMTP is
meant for personal mail apps (daily limits, automated sending isn't allowed) and Supabase Edge
Functions block SMTP ports anyway. So booking emails go through **Resend**, which sends as
noreply@easysesh.live. It uses its own DNS records on the `send.` subdomain plus a DKIM key, so it
works side by side with iCloud (iCloud keeps receiving everything).

## Booking emails (one-time setup, ~10 minutes)

1. <https://resend.com> → sign up (free: 3,000 emails/month, 100/day).
2. **Domains → Add domain** → `easysesh.live`, region **EU (Ireland)** → **Add**.
   Click **Auto configure** (signs in to Cloudflare and adds the records), or add the records it
   lists in Cloudflare → DNS by hand. Wait until the domain shows **Verified**.
3. **API Keys → Create API key** → name `EasySesh`, permission **Sending access**, domain
   `easysesh.live` → copy the key (starts with `re_`).
4. PowerShell, in the `studie-app` folder:
   ```powershell
   .\supabase.exe secrets set --project-ref gdebbieifsvspszmevwa RESEND_API_KEY=re_xxxxxxxx
   .\supabase.exe functions deploy send-push legal --project-ref gdebbieifsvspszmevwa
   ```

From then on, these notifications are also emailed (from `supabase/functions/_shared/email.ts`):
booking confirmed, new booking / request (to the studio), request declined or expired, booking
cancelled, booking moved, refund on its way. Each email has the booking reference, studio, time
(studio's time zone), total, payment method, address and a "View booking" link to easysesh.live.

## Optional: sign-up and password emails from noreply@easysesh.live

Supabase's built-in mailer sends from a Supabase address and only a few emails per hour.
Supabase → **Authentication → Emails → SMTP Settings** → **Enable custom SMTP**:

| Field | Value |
| --- | --- |
| Sender email | noreply@easysesh.live |
| Sender name | EasySesh |
| Host | smtp.resend.com |
| Port | 465 |
| Username | resend |
| Password | the same `re_…` API key |

Then raise the email rate limit under **Authentication → Rate Limits**.
