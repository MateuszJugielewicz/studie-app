import { useMemo, useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowRight, BadgeCheck, MapPin, Search, ShieldCheck, Star, TrendingUp, Wallet } from "lucide-react";
import { api } from "../lib/api";
import { EMPTY_FILTERS, Money, searchStudios, Studios } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useLoad } from "../lib/state";
import { Photo } from "../components/ui";
import { StudioCard } from "./Discover";
import { Footer } from "./Footer";

const STEPS = [
  ["Find a studio", "Search by city, price, gear, genre and free times, on a list or a map."],
  ["Book a time", "Pick a session, hours and extras like mixing or an engineer. You see the full price before you pay."],
  ["Pay your way", "Pay by card, Apple Pay or Google Pay, or in cash at the studio when the studio allows it."],
  ["Chat with the studio", "Every booking has its own chat, so details never get lost."],
];

const STUDIO_POINTS = [
  [ShieldCheck, "Every studio is reviewed by our team before it goes live."],
  [Wallet, "Payouts 2 days after each completed session, minus a 10% platform fee."],
  [TrendingUp, "Dashboard with requests, calendar, earnings and reviews."],
  [BadgeCheck, "Instant booking or approve each request yourself."],
] as const;

/** The public front page for people who aren't signed in. */
export default function Landing() {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const { data: studios } = useLoad(() => api.publishedStudios(), []);
  // Real studios only: the best rated first, promoted ones on top (same order as Discover).
  const featured = useMemo(() => searchStudios(studios ?? [], EMPTY_FILTERS, "top_rated", null), [studios]);
  const withPhotos = featured.filter((r) => r.studio.photo_urls.length > 0);
  const [line1, line2] = t("Studio time,\nbooked in minutes.").split("\n");

  function search(e: FormEvent) {
    e.preventDefault();
    navigate(query.trim() ? `/studios?q=${encodeURIComponent(query.trim())}` : "/studios");
  }

  return (
    <>
      <main>
        <section className="hero">
          <div className="hero-glow" aria-hidden />
          <div className="container hero-grid">
            <div className="stack-lg" style={{ gap: 28 }}>
              <h1 className="title-xl">{line1}{line2 && <><br /><em>{line2}</em></>}</h1>
              <p className="lead">{t("Find rooms, gear and engineers near you. See real prices and availability, book and pay in one place.")}</p>
              <form className="hero-search" onSubmit={search} role="search">
                <Search size={20} />
                <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("Studio, area or city")} aria-label={t("Studio, area or city")} />
                <button type="submit" className="btn primary">{t("Find a studio")}</button>
              </form>
              <div className="row wrap" style={{ gap: 20 }}>
                <Link to="/signup?role=studio" className="link-btn row" style={{ gap: 6 }}>{t("List your studio")}<ArrowRight size={16} /></Link>
                <span className="subhead secondary">{t("Already have an account?")} <Link to="/signin" className="semibold" style={{ color: "var(--text)", textDecoration: "underline", textUnderlineOffset: 3 }}>{t("Sign in")}</Link></span>
              </div>
            </div>
            <HeroCollage results={withPhotos.length ? withPhotos : featured} />
          </div>
        </section>

        {featured.length > 0 && (
          <section className="section-pad">
            <div className="container">
              <div className="section-head">
                <div>
                  <div className="eyebrow">{t("Top rated")}</div>
                  <h2 className="title-l">{t("Studios on EasySesh")}</h2>
                </div>
                <Link to="/studios" className="btn secondary">{t("See all studios")}<ArrowRight size={16} /></Link>
              </div>
              <div className="grid-cards">
                {featured.slice(0, 4).map((r) => <StudioCard key={r.studio.id} result={r} metric onClick={() => navigate(`/studios/${r.studio.id}`)} />)}
              </div>
            </div>
          </section>
        )}

        <section className={`section-pad ${featured.length > 0 ? "band" : ""}`}>
          <div className="container">
            <div className="section-head">
              <div>
                <div className="eyebrow">{t("How it works")}</div>
                <h2 className="title-l">{t("From search to session in four steps.")}</h2>
              </div>
            </div>
            <ol className="steps" style={{ listStyle: "none", margin: 0, padding: 0 }}>
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

        <section className="section-pad" id="studios">
          <div className="container split">
            <div className="stack-lg">
              <div className="eyebrow">{t("For studios")}</div>
              <h2 className="title-l">{t("Fill your empty hours.")}</h2>
              <p className="lead">{t("List your rooms, prices and opening hours. Artists book and pay online, and you're paid out automatically after each session.")}</p>
              <div className="row wrap" style={{ gap: 12 }}>
                <Link to="/signup?role=studio" className="btn primary large">{t("List your studio")}</Link>
                <Link to="/signin" className="btn quiet large">{t("Sign in")}</Link>
              </div>
            </div>
            <ul className="check-list card big" style={{ padding: 28 }}>
              {STUDIO_POINTS.map(([Icon, text]) => <li key={text}><Icon size={20} /><span>{t(text)}</span></li>)}
            </ul>
          </div>
        </section>

        <section className="container" style={{ paddingBottom: 88 }}>
          <div className="cta-band">
            <div className="stack" style={{ maxWidth: 520, position: "relative" }}>
              <h2 className="title-l">{t("Also on your phone")}</h2>
              <p className="secondary" style={{ margin: 0 }}>{t("Your account works everywhere: on this website and in the EasySesh app for iPhone and Android.")}</p>
            </div>
            <div className="row wrap" style={{ gap: 12 }}>
              <span className="store-badge"><span style={{ fontSize: 24, lineHeight: 1 }}></span><span><small>{t("Coming soon")}</small>App Store</span></span>
              <span className="store-badge"><span style={{ fontSize: 18, lineHeight: 1 }}>▶</span><span><small>{t("Coming soon")}</small>Google Play</span></span>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}

/** Photos of real studios on the platform, with the best one as a floating listing card. */
function HeroCollage({ results }: { results: ReturnType<typeof searchStudios> }) {
  const top = results[0]?.studio;
  // Each studio's cover first, then their other photos, so a few studios still fill all three tiles.
  const all = [...results.map((r) => r.studio.photo_urls[0]), ...results.flatMap((r) => r.studio.photo_urls.slice(1))].filter(Boolean);
  const photos = [0, 1, 2].map((i) => all[i] ?? null);
  return (
    <div className="hero-collage" aria-hidden>
      {photos.map((url, i) => <Photo key={i} url={url} />)}
      {top && (
        <Link to={`/studios/${top.id}`} className="card float row" tabIndex={-1} style={{ padding: 12, gap: 12 }}>
          <Photo url={top.photo_urls[0]} style={{ width: 52, height: 52, borderRadius: 10, flexShrink: 0 }} />
          <span className="grow" style={{ minWidth: 0 }}>
            <span className="headline clamp-1" style={{ display: "block" }}>{top.name}</span>
            <span className="caption secondary row" style={{ gap: 4 }}><MapPin size={12} /><span className="clamp-1">{Studios.publicArea(top)}</span></span>
            <span className="footnote row" style={{ gap: 8, marginTop: 2 }}>
              <span className="semibold">{format("From %@/h", Money.format(top.price_from, top.currency))}</span>
              {top.review_count > 0 && <span className="row" style={{ gap: 3 }}><Star size={12} fill="var(--accent)" color="var(--accent)" />{top.rating_average.toFixed(1)}</span>}
            </span>
          </span>
        </Link>
      )}
    </div>
  );
}
