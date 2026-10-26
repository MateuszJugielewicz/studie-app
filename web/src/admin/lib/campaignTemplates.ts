// Starting points for emails to EasySesh users. Creating one makes a draft campaign with the matching
// users already on the list (public.campaign_audience); an admin reviews and approves it before anything
// can be sent. {{name|there}} means: the user's name, or "there" when it's empty.

export interface CampaignTemplate {
  id: string;
  title: string;
  /** Who gets it (shown in the panel; the same rules as campaign_audience in the database). */
  audience: string;
  from: string;
  subject: string;
  body: string;
  footer: string;
}

const ACCOUNT_FOOTER = "You're getting this email because you have an EasySesh account. You can turn off emails any time in Settings.";

export const CAMPAIGN_TEMPLATES: CampaignTemplate[] = [
  {
    id: "artist_profile_unfinished",
    title: "Artists: unfinished profile",
    audience: "Artists who signed up 2+ days ago without adding their artist name and city.",
    from: "support",
    subject: "Your EasySesh profile is almost ready",
    body: `Hi {{name|there}},

You signed up for EasySesh but haven't finished your artist profile yet. It only takes a minute: add your artist name and city, and you're ready to find studios near you, see real prices and free times, and book a session.

Finish your profile: {{website}}

If something got in the way, just reply to this email – we read every message.

The EasySesh team`,
    footer: ACCOUNT_FOOTER,
  },
  {
    id: "studio_setup_unfinished",
    title: "Studios: listing never sent for review",
    audience: "Studio owners who signed up 2+ days ago whose studio is still a draft (or who never started one).",
    from: "support",
    subject: "Your studio isn't on EasySesh yet",
    body: `Hi {{name|there}},

You started listing your studio on EasySesh, but it hasn't been sent for review yet, so artists can't find it.

Add photos, prices and opening hours, then send it for review. We check new studios quickly and let you know as soon as you're live.

Continue your listing: {{website}}

Stuck on something? Reply to this email and we'll help you finish it.

The EasySesh team`,
    footer: ACCOUNT_FOOTER,
  },
  {
    id: "studio_changes_requested",
    title: "Studios: changes requested, not resubmitted",
    audience: "Studios we asked to change something that haven't sent their listing again in 3+ days.",
    from: "support",
    subject: "A few changes and your studio can go live",
    body: `Hi {{name|there}},

We reviewed your studio and asked for a few changes before it can go live. You can see our note in your studio editor.

Once you've made the changes, send the studio for review again and we'll take another look.

Open your studio: {{website}}

If anything in our note is unclear, just reply – we're happy to help.

The EasySesh team`,
    footer: ACCOUNT_FOOTER,
  },
  {
    id: "email_unverified",
    title: "Everyone: email not confirmed",
    audience: "Artists and studio owners who haven't confirmed their email address 2+ days after signing up.",
    from: "support",
    subject: "Please confirm your email address",
    body: `Hi {{name|there}},

You haven't confirmed your email address on EasySesh yet. Until you do, artists can't book sessions or message studios, and studios can't be sent for review.

Sign in at {{website}} and press "Resend email" in the banner at the top of the page to get a new confirmation link.

The EasySesh team`,
    footer: ACCOUNT_FOOTER,
  },
  {
    id: "artist_no_recent_bookings",
    title: "Artists: no booking in 60 days",
    audience: "Artists with a finished profile and no booking in 60 days (or none at all after 30 days) who said yes to news and offers.",
    from: "easysesh",
    subject: "Time for a new session?",
    body: `Hi {{name|there}},

It's been a while since your last session on EasySesh. Browse studios near {{city|you}}, compare prices and free times, and book in a few minutes – pay online or, where the studio allows it, in cash.

Find a studio: {{website}}

The EasySesh team`,
    footer: "You're getting this email because you said yes to news and offers from EasySesh. You can turn this off any time in Settings.",
  },
  {
    id: "studio_no_recent_bookings",
    title: "Studios: no booking request in 30 days",
    audience: "Approved, visible studios (live for 30+ days) without a booking request in the last 30 days.",
    from: "support",
    subject: "A few ways to get more bookings",
    body: `Hi {{name|there}},

{{name|Your studio}} hasn't had a booking request on EasySesh in the last 30 days. A few things that help artists choose you:

• Photos: bright photos of every room, the control room and your best gear.
• Prices: a clear hourly price and at least one package, e.g. "Vocal session, 2 hours".
• Instant book: artists book more when they get an instant confirmation.
• Opening hours: keep your hours and calendar up to date so your free times show.
• Offers: a first-time discount can bring new artists through the door.

See your studio as artists see it: {{website}}

Reply to this email if you'd like us to look at your listing with you.

The EasySesh team`,
    footer: "You're getting this email because you list a studio on EasySesh. You can turn off emails any time in Settings.",
  },
];
