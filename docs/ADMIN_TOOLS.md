# Admin tools (admin.easysesh.live)

## Ranks
| Rank | Can |
| --- | --- |
| Owner | Everything, plus **Team** (who is an admin) and **Audit log** |
| Admin | Everything except Team and Audit log |
| Support | See everything; only answer support requests; email from support@ |

Ranks are enforced by the database, not just hidden in the panel. Add people under **Team** by the
email of their EasySesh account (they must sign up first; studio-owner accounts can't be admins).
There must always be at least one owner.

## “Why?” – explanations and account-change emails
Every change made in the panel asks for a short explanation. It is:
- saved in the **Audit log** with who, when, and exactly what changed (old → new), and
- when the change affects someone's account (profile, studio, offers, codes, fees, moderation,
  reviews), emailed to them from **noreply@easysesh.live** with the list of changes and the
  explanation. Replies go to **support@easysesh.live**, so they can object. They also get an in-app
  notification.

## View as user
Users → open a user → **View as user** (or Studios → **View as studio**). The panel makes a session for
that person and shows a link; it opens the website in a new tab exactly as they see it, with a black
“Viewing as …” bar. It is **view only**: the database, file storage and server functions refuse every
change from that session. **Stop viewing** ends it. Every use is in the audit log.

## Email
**Email** sends from an @easysesh.live address with the EasySesh design (support staff: support@;
admins: support@, easysesh@, noreply@; owners: any address). Replies arrive in iCloud. The last 200
emails are listed. At most 300 a day.

## Banners
**Banners** puts a bar at the top of the website and both apps: info, warning, outage (red) or
success; for everyone, guests, artists or studios; optional link and end time; can be made
impossible to close.

## Auto-flags
New or changed messages, bios, studio texts and reviews are checked for mentions of minors,
paying/booking outside EasySesh, illegal things (drugs, weapons, sex work), and – in messages only –
phone numbers, emails and chat apps. A match creates a report in **Moderation** marked “Automatic
flag” with the matching text; nothing is hidden or blocked automatically. Edit the word lists under
**Auto-flags** (there's a box to test a text).

## Deleting accounts and studios
Admins and owners: **Users → Delete account**, **Studios → Delete studio** (asks why; the person is
emailed from noreply@ with the reason). Upcoming bookings are cancelled with full refunds.
- An account with booking history (or a studio) is anonymised and soft-deleted so receipts stay
  valid; otherwise it's removed completely. A studio owner's studio goes offline.
- A studio that never had bookings is removed completely; otherwise it's taken offline and hidden
  (the owner's account stays).
Admin accounts can't be deleted here – remove them from the team first.

## Promotions (studios and artists)

Studios buy a period at the top of Discover and search; artists buy a place first in the studios'
artist search. Both get a "Promoted" tag. They pay on the website (Studio → Promotion, or Profile →
Promotion) with Stripe, and the promotion starts by itself (`promotion-payment` + `stripe-webhook`).
Prices are in `promotion_price` (artists pay in EUR). The apps only show the status and the tag; they
don't sell or link to promotions (App Store 3.1.3 / Google Play payments rules).

Admins can give a free promotion and end one: studios in Studios, artists in Users, and both in
Promotions ("End now", or "Paid – activate" for an order paid some other way).
