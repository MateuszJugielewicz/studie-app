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
