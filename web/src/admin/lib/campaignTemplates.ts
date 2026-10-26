// Starting points for emails to EasySesh users, in English and Danish. Creating one makes a draft
// campaign with the matching users already on the list (public.campaign_audience); an admin reviews
// and approves it before anything can be sent. {{name|there}} means: the user's name, or "there"
// when it's empty.

export type CampaignLanguage = "en" | "da";

export const CAMPAIGN_LANGUAGES: { id: CampaignLanguage; title: string }[] = [
  { id: "en", title: "English" },
  { id: "da", title: "Dansk" },
];

export interface CampaignText { subject: string; body: string; footer: string }

export interface CampaignTemplate {
  id: string;
  title: string;
  /** Who gets it (shown in the panel; the same rules as campaign_audience in the database). */
  audience: string;
  from: string;
  text: Record<CampaignLanguage, CampaignText>;
}

const FOOTER = {
  account: {
    en: "You're getting this email because you have an EasySesh account. You can turn off emails any time in Settings.",
    da: "Du får denne mail, fordi du har en konto på EasySesh. Du kan altid slå mails fra under Indstillinger.",
  },
  studio: {
    en: "You're getting this email because you list a studio on EasySesh. You can turn off emails any time in Settings.",
    da: "Du får denne mail, fordi du har et studie på EasySesh. Du kan altid slå mails fra under Indstillinger.",
  },
  marketing: {
    en: "You're getting this email because you said yes to news and offers from EasySesh. You can turn this off any time in Settings.",
    da: "Du får denne mail, fordi du har sagt ja til nyheder og tilbud fra EasySesh. Du kan altid slå det fra under Indstillinger.",
  },
};

export const CAMPAIGN_TEMPLATES: CampaignTemplate[] = [
  {
    id: "artist_profile_unfinished",
    title: "Artists: unfinished profile",
    audience: "Artists who signed up 2+ days ago without adding their artist name and city.",
    from: "support",
    text: {
      en: {
        subject: "Your EasySesh profile is almost ready",
        body: `Hi {{name|there}},

You signed up for EasySesh but haven't finished your artist profile yet. It only takes a minute: add your artist name and city, and you're ready to find studios near you, see real prices and free times, and book a session.

Finish your profile: {{website}}

If something got in the way, just reply to this email – we read every message.

The EasySesh team`,
        footer: FOOTER.account.en,
      },
      da: {
        subject: "Din EasySesh-profil er næsten klar",
        body: `Hej {{name|der}},

Du har oprettet en konto på EasySesh, men din artistprofil er ikke helt færdig endnu. Det tager kun et minut: Tilføj dit artistnavn og din by, så kan du finde studier i nærheden, se rigtige priser og ledige tider og booke en session.

Gør din profil færdig: {{website}}

Hvis noget drillede, så svar bare på denne mail – vi læser alle beskeder.

Hilsen EasySesh`,
        footer: FOOTER.account.da,
      },
    },
  },
  {
    id: "studio_setup_unfinished",
    title: "Studios: listing never sent for review",
    audience: "Studio owners who signed up 2+ days ago whose studio is still a draft (or who never started one).",
    from: "support",
    text: {
      en: {
        subject: "Your studio isn't on EasySesh yet",
        body: `Hi {{name|there}},

You started listing your studio on EasySesh, but it hasn't been sent for review yet, so artists can't find it.

Add photos, prices and opening hours, then send it for review. We check new studios quickly and let you know as soon as you're live.

Continue your listing: {{website}}

Stuck on something? Reply to this email and we'll help you finish it.

The EasySesh team`,
        footer: FOOTER.account.en,
      },
      da: {
        subject: "Dit studie er ikke på EasySesh endnu",
        body: `Hej {{name|der}},

Du er gået i gang med at oprette dit studie på EasySesh, men det er ikke sendt til godkendelse endnu, så artister kan ikke finde det.

Tilføj billeder, priser og åbningstider, og send det til godkendelse. Vi gennemgår nye studier hurtigt og giver besked, så snart I er live.

Fortsæt med dit studie: {{website}}

Sidder du fast? Svar på denne mail, så hjælper vi dig i mål.

Hilsen EasySesh`,
        footer: FOOTER.account.da,
      },
    },
  },
  {
    id: "studio_changes_requested",
    title: "Studios: changes requested, not resubmitted",
    audience: "Studios we asked to change something that haven't sent their listing again in 3+ days.",
    from: "support",
    text: {
      en: {
        subject: "A few changes and your studio can go live",
        body: `Hi {{name|there}},

We reviewed your studio and asked for a few changes before it can go live. You can see our note in your studio editor.

Once you've made the changes, send the studio for review again and we'll take another look.

Open your studio: {{website}}

If anything in our note is unclear, just reply – we're happy to help.

The EasySesh team`,
        footer: FOOTER.account.en,
      },
      da: {
        subject: "Et par rettelser, så kan dit studie gå live",
        body: `Hej {{name|der}},

Vi har gennemgået dit studie og bedt om et par rettelser, før det kan gå live. Du kan se vores note i din studieeditor.

Når du har lavet rettelserne, så send studiet til godkendelse igen, så kigger vi på det.

Åbn dit studie: {{website}}

Er noget i vores note uklart, så svar bare – vi hjælper gerne.

Hilsen EasySesh`,
        footer: FOOTER.account.da,
      },
    },
  },
  {
    id: "email_unverified",
    title: "Everyone: email not confirmed",
    audience: "Artists and studio owners who haven't confirmed their email address 2+ days after signing up.",
    from: "support",
    text: {
      en: {
        subject: "Please confirm your email address",
        body: `Hi {{name|there}},

You haven't confirmed your email address on EasySesh yet. Until you do, artists can't book sessions or message studios, and studios can't be sent for review.

Sign in at {{website}} and press "Resend email" in the banner at the top of the page to get a new confirmation link.

The EasySesh team`,
        footer: FOOTER.account.en,
      },
      da: {
        subject: "Bekræft venligst din e-mailadresse",
        body: `Hej {{name|der}},

Du har ikke bekræftet din e-mailadresse på EasySesh endnu. Indtil du gør det, kan artister ikke booke sessioner eller skrive til studier, og studier kan ikke sendes til godkendelse.

Log ind på {{website}} og tryk "Send e-mail igen" i banneret øverst på siden for at få et nyt bekræftelseslink.

Hilsen EasySesh`,
        footer: FOOTER.account.da,
      },
    },
  },
  {
    id: "artist_no_recent_bookings",
    title: "Artists: no booking in 60 days",
    audience: "Artists with a finished profile and no booking in 60 days (or none at all after 30 days) who said yes to news and offers.",
    from: "easysesh",
    text: {
      en: {
        subject: "Time for a new session?",
        body: `Hi {{name|there}},

It's been a while since your last session on EasySesh. Browse studios near {{city|you}}, compare prices and free times, and book in a few minutes – pay online or, where the studio allows it, in cash.

Find a studio: {{website}}

The EasySesh team`,
        footer: FOOTER.marketing.en,
      },
      da: {
        subject: "Tid til en ny session?",
        body: `Hej {{name|der}},

Det er et stykke tid siden, du sidst har været i studiet via EasySesh. Find studier i nærheden af {{city|dig}}, sammenlign priser og ledige tider, og book på få minutter – betal online eller kontant i studiet, hvis studiet tillader det.

Find et studie: {{website}}

Hilsen EasySesh`,
        footer: FOOTER.marketing.da,
      },
    },
  },
  {
    id: "studio_no_recent_bookings",
    title: "Studios: no booking request in 30 days",
    audience: "Approved, visible studios (live for 30+ days) without a booking request in the last 30 days.",
    from: "support",
    text: {
      en: {
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
        footer: FOOTER.studio.en,
      },
      da: {
        subject: "Et par måder at få flere bookinger på",
        body: `Hej {{name|der}},

{{name|Jeres studie}} har ikke fået en bookingforespørgsel på EasySesh de sidste 30 dage. Her er et par ting, der får artister til at vælge jer:

• Billeder: lyse billeder af alle rum, kontrolrummet og jeres bedste udstyr.
• Priser: en klar timepris og mindst én pakke, fx "Vokalsession, 2 timer".
• Instant book: artister booker mere, når de får en bekræftelse med det samme.
• Åbningstider: hold åbningstider og kalender opdateret, så jeres ledige tider vises.
• Tilbud: en rabat til nye kunder kan få nye artister indenfor.

Se jeres studie, som artister ser det: {{website}}

Svar på denne mail, hvis I vil have os til at kigge på jeres profil sammen med jer.

Hilsen EasySesh`,
        footer: FOOTER.studio.da,
      },
    },
  },
];
