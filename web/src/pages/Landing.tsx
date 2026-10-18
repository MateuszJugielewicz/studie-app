import { Link } from "react-router-dom";
import { BadgeCheck, CalendarCheck, CreditCard, MapPin, MessagesSquare, Search, ShieldCheck, Sparkles, TrendingUp, Wallet } from "lucide-react";
import { t } from "../lib/i18n";
import { IconTile, Logo, Tiles } from "../components/ui";
import { Footer } from "./Footer";

const BARS = [0.3, 0.55, 0.45, 0.7, 0.4, 0.85, 0.6, 1, 0.75, 0.9, 0.5, 0.65, 0.35, 0.55, 0.3];

/** The public front page for people who aren't signed in (the app's welcome screen, for the web). */
export default function Landing() {
  return (
    <>
      <main className="page">
        <section className="hero">
          <div className="stack-lg">
            <div className="meter" style={{ height: 70, maxWidth: 360 }}>
              {BARS.map((h, i) => <span key={i} style={{ height: `${h * 100}%`, animationDelay: `${i * 90}ms`, animationDuration: `${1.1 + (i % 4) * 0.2}s` }} />)}
            </div>
            <h1 className="title-xl" style={{ whiteSpace: "pre-line" }}>{t("Studio time,\nbooked in minutes.")}</h1>
            <p className="secondary" style={{ fontSize: 19, margin: 0, maxWidth: 520 }}>{t("Find rooms, gear and engineers near you. See real prices and availability, book and pay in one place.")}</p>
            <div className="row wrap" style={{ gap: 12 }}>
              <Link to="/signup" className="btn primary">{t("Find a studio")}</Link>
              <Link to="/signup?role=studio" className="btn secondary">{t("List your studio")}</Link>
            </div>
            <div className="row wrap" style={{ gap: 16 }}>
              <Link to="/studios" className="link-btn">{t("Look around first")}</Link>
              <span className="subhead secondary">{t("Already have an account?")} <Link to="/signin" className="bold" style={{ color: "var(--text)" }}>{t("Sign in")}</Link></span>
            </div>
          </div>
          <PhonePreview />
        </section>

        <section className="stack-lg" style={{ marginTop: 40 }}>
          <div className="eyebrow">{t("How it works")}</div>
          <div className="grid-cards" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))" }}>
            <Feature icon={Search} colors={Tiles.signal} title="Find a studio" text="Search by city, price, gear, genre and free times, on a list or a map." />
            <Feature icon={CalendarCheck} colors={Tiles.violet} title="Book a time" text="Pick a session, hours and extras like mixing or an engineer. You see the full price before you pay." />
            <Feature icon={CreditCard} colors={Tiles.ocean} title="Pay your way" text="Pay by card, Apple Pay or Google Pay, or in cash at the studio when the studio allows it." />
            <Feature icon={MessagesSquare} colors={Tiles.mint} title="Chat with the studio" text="Every booking has its own chat, so details never get lost." />
          </div>
        </section>

        <section className="card big" style={{ marginTop: 48, padding: 28 }}>
          <div className="split">
            <div className="stack">
              <div className="eyebrow">{t("For studios")}</div>
              <h2 className="title-l">{t("Fill your empty hours.")}</h2>
              <p className="secondary" style={{ margin: 0 }}>{t("List your rooms, prices and opening hours. Artists book and pay online, and you're paid out automatically after each session.")}</p>
              <div><Link to="/signup?role=studio" className="btn primary">{t("List your studio")}</Link></div>
            </div>
            <div className="stack">
              <Point icon={ShieldCheck} text="Every studio is reviewed by our team before it goes live." />
              <Point icon={Wallet} text="Payouts 2 days after each completed session, minus a 10% platform fee." />
              <Point icon={TrendingUp} text="Dashboard with requests, calendar, earnings and reviews." />
              <Point icon={BadgeCheck} text="Instant booking or approve each request yourself." />
            </div>
          </div>
        </section>

        <section className="stack" style={{ marginTop: 48, alignItems: "center", textAlign: "center" }}>
          <IconTile icon={Sparkles} size={48} colors={Tiles.violet} />
          <h2 className="title-l">{t("Also on your phone")}</h2>
          <p className="secondary" style={{ margin: 0, maxWidth: 520 }}>{t("Your account works everywhere: on this website and in the EasySesh app for iPhone and Android.")}</p>
          <div className="row wrap" style={{ justifyContent: "center", gap: 12 }}>
            <span className="store-badge"><span style={{ fontSize: 26 }}></span><span><small>{t("Coming soon")}</small>App Store</span></span>
            <span className="store-badge"><span style={{ fontSize: 22 }}>▶</span><span><small>{t("Coming soon")}</small>Google Play</span></span>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}

function Feature({ icon, colors, title, text }: { icon: typeof Search; colors: string[]; title: string; text: string }) {
  return (
    <div className="card" style={{ padding: 20 }}>
      <IconTile icon={icon} size={44} colors={colors} />
      <div className="headline" style={{ marginTop: 14 }}>{t(title)}</div>
      <div className="subhead secondary" style={{ marginTop: 4 }}>{t(text)}</div>
    </div>
  );
}

function Point({ icon: Icon, text }: { icon: typeof Search; text: string }) {
  return <div className="row top"><Icon size={20} color="var(--accent)" style={{ flexShrink: 0, marginTop: 2 }} /><span>{t(text)}</span></div>;
}

/** A small, static mock of the app's discover screen. */
function PhonePreview() {
  const cards = [
    { name: "Night Owl Studio", area: "Exarchia, Athens", price: "€25", rating: "4.9", colors: ["#E0246F", "#6A4DF5"] },
    { name: "Bluebird Rooms", area: "Nørrebro, Copenhagen", price: "€32", rating: "4.8", colors: ["#D9431E", "#E0246F"] },
    { name: "Tape Room", area: "Kreuzberg, Berlin", price: "€19", rating: "4.7", colors: ["#6A4DF5", "#0FA5D6"] },
  ];
  return (
    <div className="phone hide-mobile" aria-hidden>
      <div>
        <div style={{ position: "absolute", inset: 0, background: "radial-gradient(circle at 15% 0%, color-mix(in srgb, var(--accent) 35%, transparent), transparent 45%), radial-gradient(circle at 90% 10%, color-mix(in srgb, var(--magenta) 30%, transparent), transparent 45%), radial-gradient(circle at 50% 35%, color-mix(in srgb, var(--violet) 22%, transparent), transparent 50%)" }} />
        <div style={{ position: "relative", padding: "38px 16px 16px" }} className="stack">
          <div className="eyebrow" style={{ fontSize: 10 }}><MapPin size={10} /> Athens</div>
          <div style={{ fontSize: 26, fontWeight: 800, letterSpacing: "-0.02em" }}>{t("Discover")}</div>
          <div className="field" style={{ height: 40, borderRadius: 14 }}><Search size={14} /><span className="caption tertiary">{t("Search city, studio, gear…")}</span></div>
          {cards.map((c) => (
            <div key={c.name} className="card zero" style={{ borderRadius: 18 }}>
              <div style={{ height: 82, background: `linear-gradient(135deg, ${c.colors[0]}, ${c.colors[1]})` }} />
              <div style={{ padding: "8px 12px" }}>
                <div className="row spread"><span className="footnote bold">{c.name}</span><span className="caption bold">★ {c.rating}</span></div>
                <div className="row spread"><span className="caption2 secondary">{c.area}</span><span className="caption2 bold">{c.price}/h</span></div>
              </div>
            </div>
          ))}
          <div style={{ textAlign: "center" }}><Logo size={14} /></div>
        </div>
      </div>
    </div>
  );
}
