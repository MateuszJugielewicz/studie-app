import { Link } from "react-router-dom";
import { Globe, Instagram } from "lucide-react";
import { LANGUAGES, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { Logo } from "../components/ui";
import { LEGAL } from "./Legal";
import { CONTACT } from "../lib/config";

export function Footer() {
  const app = useApp();
  return (
    <footer className="footer">
      <div className="inner">
        <div className="stack" style={{ gap: 12, maxWidth: 320 }}>
          <Logo size={22} />
          <span>{t("Book recording studios near you.")}</span>
          <a className="social-link" href={CONTACT.instagram} target="_blank" rel="noopener noreferrer" aria-label={t("EasySesh on Instagram")}>
            <Instagram size={18} />{CONTACT.instagramHandle}
          </a>
        </div>
        <div className="stack" style={{ gap: 10 }}>
          <h4>EasySesh</h4>
          <Link to="/studios">{t("Find a studio")}</Link>
          <Link to="/for-studios">{t("List your studio")}</Link>
          <Link to="/about">{t("About us")}</Link>
          <Link to="/signin">{t("Sign in")}</Link>
        </div>
        <div className="stack" style={{ gap: 10 }}>
          <h4>{t("Contact")}</h4>
          <a href={`mailto:${CONTACT.support}`}>{CONTACT.support}</a>
          <a href={`mailto:${CONTACT.general}`}>{CONTACT.general}</a>
          <a href={CONTACT.instagram} target="_blank" rel="noopener noreferrer">Instagram</a>
        </div>
        <div className="stack" style={{ gap: 10 }}>
          <h4>{t("Legal")}</h4>
          {Object.entries(LEGAL).map(([key, doc]) => <Link key={key} to={`/legal/${key}`}>{t(doc.title)}</Link>)}
        </div>
      </div>
      <div className="bottom">
        <span className="footnote">© {new Date().getFullYear()} EasySesh</span>
        <label className="row footnote" style={{ gap: 8 }}>
          <Globe size={16} />
          <select value={app.language} onChange={(e) => app.changeLanguage(e.target.value)} aria-label={t("Language")}>
            {LANGUAGES.map((l) => <option key={l.code} value={l.code}>{l.flag} {l.name}</option>)}
          </select>
        </label>
      </div>
    </footer>
  );
}
