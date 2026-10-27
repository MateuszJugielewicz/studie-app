import { Link } from "react-router-dom";
import { BadgePercent, CalendarClock, CheckCircle2, Coins, KeyRound, LockKeyhole, Tag, type LucideIcon } from "lucide-react";
import { PlatformConfig } from "../lib/config";
import { format, t } from "../lib/i18n";
import { Footer } from "./Footer";

/** What a studio controls, so studios can see the setup before they sign up. */
const CONTROLS: { icon: LucideIcon; title: string; points: string[] }[] = [
  {
    icon: Coins, title: "Prices",
    points: [
      "Session types with their own hourly price and minimum hours (e.g. Recording, Studio without engineer, Mixing)",
      "Different prices at certain times, e.g. evenings or weekends",
      "Add-ons like engineer, producer, mixing or mastering – per hour, per session or per track",
      "Your own currency",
    ],
  },
  {
    icon: CalendarClock, title: "Times",
    points: [
      "Opening hours for each weekday, also past midnight",
      "Minimum notice up to 72 hours – e.g. no same-day bookings",
      "How far ahead artists can book",
      "A buffer between sessions, and block times in your calendar",
    ],
  },
  {
    icon: CheckCircle2, title: "Booking rules",
    points: [
      "Instant booking, or approve every request yourself",
      "Your cancellation policy: flexible, moderate or strict",
      "Full payment or a deposit up front – and whether you accept cash",
      "Your own booking terms (overtime, damage, guests…)",
    ],
  },
  {
    icon: KeyRound, title: "After a booking",
    points: [
      "Arrival info sent automatically when a booking is confirmed – e.g. door or key-box code, parking, what to bring",
      "Card bookings are only confirmed once they're paid, so you don't have to check",
      "Messages with the artist, and check-in when they arrive",
    ],
  },
  {
    icon: Tag, title: "Offers & promo codes",
    points: [
      "Offers that apply automatically, e.g. Mixing 20% off",
      "Your own promo codes, e.g. 15% off studio time with a code",
    ],
  },
  {
    icon: LockKeyhole, title: "Your details",
    points: [
      "Your phone number is only for EasySesh – artists write to you in Messages",
      "Artists see the area before booking and the full address after booking",
      "Your CVR / VAT number is only seen by EasySesh",
    ],
  },
];

const STEPS: [string, string][] = [
  ["Create your listing", "Photos, prices, opening hours and rules. Save as you go – nothing is public yet."],
  ["Submit for review", "We check every studio, usually within 1–2 business days."],
  ["Go live", "Artists find you, book and pay – and you can change everything at any time."],
];

export default function ForStudios() {
  return (
    <>
      <main>
        <section className="hero">
          <div className="hero-glow" aria-hidden />
          <div className="container" style={{ position: "relative", zIndex: 1, padding: "72px var(--gutter) 56px", maxWidth: 1320 }}>
            <div className="stack-lg" style={{ maxWidth: 760, gap: 20 }}>
              <div className="eyebrow">{t("For studios")}</div>
              <h1 className="title-xl" style={{ fontSize: "clamp(38px, 5.4vw, 60px)" }}>{t("See exactly how your studio works on EasySesh")}</h1>
              <p className="lead">{t("Everything you can set up – prices, times, rules and payments – before you sign up. It's free to list your studio, and you only pay when you get booked.")}</p>
              <div className="row wrap" style={{ gap: 12 }}>
                <Link to="/signup?role=studio" className="btn primary large">{t("List your studio")}</Link>
                <a href="#fees" className="btn secondary large">{t("Fees & payouts")}</a>
              </div>
            </div>
          </div>
        </section>

        <section className="section-pad">
          <div className="container">
            <div className="section-head">
              <div>
                <div className="eyebrow">{t("You decide")}</div>
                <h2 className="title-l">{t("What you can set up")}</h2>
              </div>
            </div>
            <div className="setup-grid">
              {CONTROLS.map(({ icon: Icon, title, points }) => (
                <div key={title} className="card setup-card">
                  <span className="setup-icon"><Icon size={20} /></span>
                  <h3 className="title-m" style={{ fontSize: 19 }}>{t(title)}</h3>
                  <ul>{points.map((p) => <li key={p}>{t(p)}</li>)}</ul>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="section-pad band" id="fees">
          <div className="container split">
            <div className="stack">
              <div className="eyebrow">{t("Fees & payouts")}</div>
              <h2 className="title-l">{t("Simple: you only pay when you get booked.")}</h2>
              <p className="lead">{t("No subscription, no sign-up fee and no lock-in. You can pause or remove your studio at any time.")}</p>
            </div>
            <ul className="check-list card big" style={{ padding: 28 }}>
              <li><CheckCircle2 size={20} /><span>{t("Free to list your studio")}</span></li>
              <li><BadgePercent size={20} /><span>{format("%lld%% platform fee per booking – the first studios pay only 5%%", PlatformConfig.PLATFORM_FEE_PERCENT)}</span></li>
              <li><Coins size={20} /><span>{t("Card fees (Stripe) are paid by EasySesh – never taken from your payout")}</span></li>
              <li><CalendarClock size={20} /><span>{format("Paid out %lld days after each completed session", PlatformConfig.PAYOUT_DELAY_DAYS)}</span></li>
              {!PlatformConfig.PAYMENTS_LIVE && <li><LockKeyhole size={20} /><span>{t("Card payments are launching soon – we'll email you before they go live.")}</span></li>}
            </ul>
          </div>
        </section>

        <section className="section-pad">
          <div className="container">
            <div className="section-head">
              <div>
                <div className="eyebrow">{t("Getting started")}</div>
                <h2 className="title-l">{t("Live in three steps.")}</h2>
              </div>
            </div>
            <ol className="steps steps-3" style={{ listStyle: "none", margin: 0, padding: 0 }}>
              {STEPS.map(([title, text], i) => (
                <li key={title} style={{ padding: "28px 24px", display: "flex", flexDirection: "column", gap: 8 }}>
                  <span className="num">0{i + 1}</span>
                  <span className="title-m" style={{ fontSize: 19 }}>{t(title)}</span>
                  <span className="subhead secondary">{t(text)}</span>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="container" style={{ paddingBottom: 88 }}>
          <div className="cta-band">
            <div className="stack" style={{ maxWidth: 560, position: "relative" }}>
              <h2 className="title-l">{t("Ready to fill your empty hours?")}</h2>
              <p className="secondary" style={{ margin: 0 }}>{t("Questions first? Write to us – we're happy to help you set up your listing.")}</p>
            </div>
            <div className="row wrap" style={{ gap: 12, position: "relative" }}>
              <Link to="/signup?role=studio" className="btn primary large">{t("List your studio")}</Link>
              <Link to="/about" className="btn secondary large">{t("Contact us")}</Link>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
