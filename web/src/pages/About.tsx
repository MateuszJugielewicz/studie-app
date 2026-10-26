import { Link } from "react-router-dom";
import { Mail, MapPin } from "lucide-react";
import { t } from "../lib/i18n";
import { CONTACT } from "../lib/config";
import { Footer } from "./Footer";

const FOUNDERS = [
  { name: "Mateusz Jugielewicz", role: "Founder & owner", photo: "/team/mateusz-jugielewicz.jpg" },
  { name: "Sebastian Bartosik", role: "Co-founder", photo: "/team/sebastian-bartosik.jpg" },
];

/** Who runs EasySesh. */
export default function About() {
  return (
    <>
      <main>
        <section className="hero">
          <div className="hero-glow" aria-hidden />
          <div className="container" style={{ position: "relative", zIndex: 1, padding: "72px var(--gutter) 64px", maxWidth: 1320 }}>
            <div className="stack-lg" style={{ maxWidth: 760, gap: 20 }}>
              <div className="eyebrow">{t("About us")}</div>
              <h1 className="title-xl" style={{ fontSize: "clamp(38px, 5.4vw, 60px)" }}>{t("The people behind EasySesh")}</h1>
              <p className="lead">{t("EasySesh was founded by Mateusz Jugielewicz, who runs it together with co-founder Sebastian Bartosik. We both live in Greece.")}</p>
            </div>
          </div>
        </section>

        <section className="section-pad">
          <div className="container team-grid">
            {FOUNDERS.map((f) => (
              <figure key={f.name} className="founder">
                <img src={f.photo} alt={f.name} width={800} height={1000} loading="lazy" />
                <figcaption>
                  <div className="title-m">{f.name}</div>
                  <div className="secondary">{t(f.role)}</div>
                  <div className="row footnote secondary" style={{ gap: 6, marginTop: 6 }}><MapPin size={14} />{t("Lives in Greece")}</div>
                </figcaption>
              </figure>
            ))}
          </div>
        </section>

        <section className="section-pad band">
          <div className="container split">
            <div className="stack">
              <div className="eyebrow">{t("How it started")}</div>
              <h2 className="title-l">{t("Finding a studio shouldn't be the hard part.")}</h2>
            </div>
            <div className="stack" style={{ gap: 16 }}>
              <p className="lead" style={{ color: "var(--text)" }}>{t("The idea came from Mateusz's own experience: finding a studio that would actually let you in was harder than it should be. You message a few places, wait for answers, and still don't know what a session costs or when they're free.")}</p>
              <p className="lead">{t("There are already plenty of platforms, but that's part of the problem. Studios are spread across different sites and apps, and it's hard to know which one to use, let alone which studio is right for you.")}</p>
              <p className="lead">{t("EasySesh is our answer: one place built only for studio time, with real prices, real free times and bookings that are confirmed and paid, not left waiting in someone's inbox.")}</p>
              <div className="row wrap" style={{ gap: 12, marginTop: 8 }}>
                <Link to="/studios" className="btn primary">{t("Find a studio")}</Link>
                <Link to="/signup?role=studio" className="btn secondary">{t("List your studio")}</Link>
              </div>
            </div>
          </div>
        </section>

        <section className="container section-pad">
          <div className="cta-band">
            <div className="stack" style={{ maxWidth: 560, position: "relative" }}>
              <h2 className="title-l">{t("Get in touch")}</h2>
              <p className="secondary" style={{ margin: 0 }}>{t("Questions, ideas or feedback? Write to us – we read every message.")}</p>
            </div>
            <a className="btn secondary large" href={`mailto:${CONTACT.general}`}><Mail size={18} />{CONTACT.general}</a>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
