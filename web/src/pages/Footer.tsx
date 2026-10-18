import { Link } from "react-router-dom";
import { Globe } from "lucide-react";
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
        <div className="stack" style={{ gap: 8 }}>
          <Logo size={20} />
          <span>{t("Book recording studios near you.")}</span>
          <label className="row" style={{ gap: 6 }}>
            <Globe size={16} />
            <select value={app.language} onChange={(e) => app.changeLanguage(e.target.value)} style={{ background: "transparent", border: 0, color: "inherit", cursor: "pointer" }} aria-label={t("Language")}>
              {LANGUAGES.map((l) => <option key={l.code} value={l.code}>{l.flag} {l.name}</option>)}
            </select>
          </label>
        </div>
        <div className="stack" style={{ gap: 6 }}>
          <span className="semibold" style={{ color: "var(--text)" }}>EasySesh</span>
          <Link to="/studios">{t("Find a studio")}</Link>
          <Link to="/signup?role=studio">{t("List your studio")}</Link>
          <Link to="/signin">{t("Sign in")}</Link>
        </div>
        <div className="stack" style={{ gap: 6 }}>
          <span className="semibold" style={{ color: "var(--text)" }}>{t("Contact")}</span>
          <a href={`mailto:${CONTACT.support}`}>{CONTACT.support}</a>
          <a href={`mailto:${CONTACT.general}`}>{CONTACT.general}</a>
        </div>
        <div className="stack" style={{ gap: 6 }}>
          <span className="semibold" style={{ color: "var(--text)" }}>{t("Legal")}</span>
          {Object.entries(LEGAL).map(([key, doc]) => <Link key={key} to={`/legal/${key}`}>{t(doc.title)}</Link>)}
        </div>
      </div>
      <div style={{ maxWidth: 1100, margin: "18px auto 0" }} className="caption tertiary">© {new Date().getFullYear()} EasySesh</div>
    </footer>
  );
}
