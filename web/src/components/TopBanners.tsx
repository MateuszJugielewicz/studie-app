// Bars under the top bar: the admin "view as" notice and banners from the EasySesh team.
import { useEffect, useState } from "react";
import { CircleAlert, Eye, Info, Megaphone, PartyPopper, X } from "lucide-react";
import { api } from "../lib/api";
import { t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { viewAs } from "../lib/viewAs";
import type { SiteBanner } from "../lib/types";

const DISMISSED = "easysesh.dismissedBanners";
const readDismissed = (): string[] => { try { return JSON.parse(localStorage.getItem(DISMISSED) ?? "[]"); } catch { return []; } };

export function ViewAsBar() {
  const app = useApp();
  const viewing = viewAs();
  if (!viewing) return null;
  const stop = async () => {
    await app.signOut();
    window.close();
    window.location.href = "/";
  };
  return (
    <div className="top-banner view-as" role="status">
      <Eye size={18} style={{ flexShrink: 0 }} />
      <span><strong>Viewing as {viewing.email}</strong> ({viewing.role.replace("_", " ")}) · view only, nothing can be changed.</span>
      <button className="btn secondary small" onClick={stop}>Stop viewing</button>
    </div>
  );
}

export function SiteBanners() {
  const app = useApp();
  const [banners, setBanners] = useState<SiteBanner[]>([]);
  const [dismissed, setDismissed] = useState<string[]>(readDismissed);
  useEffect(() => {
    const load = () => api.siteBanners().then(setBanners).catch(() => undefined);
    load();
    const timer = window.setInterval(load, 5 * 60_000);
    return () => window.clearInterval(timer);
  }, []);
  const role = app.account?.role;
  const shown = banners.filter((b) => !dismissed.includes(b.id) && (b.audience === "everyone" || (b.audience === "guests" ? !role : b.audience === role)));
  if (shown.length === 0) return null;
  const dismiss = (id: string) => {
    const next = [...dismissed, id].slice(-50);
    setDismissed(next);
    try { localStorage.setItem(DISMISSED, JSON.stringify(next)); } catch { /* ignore */ }
  };
  const Icon = (kind: SiteBanner["kind"]) => (kind === "outage" ? CircleAlert : kind === "warning" ? Megaphone : kind === "success" ? PartyPopper : Info);
  return (
    <>
      {shown.map((b) => {
        const I = Icon(b.kind);
        return (
          <div key={b.id} className={`top-banner ${b.kind}`} role={b.kind === "outage" ? "alert" : "status"}>
            <I size={18} style={{ flexShrink: 0 }} />
            <span>
              <strong>{b.title}</strong>{b.body && <> {b.body}</>}
              {b.link_url && <> <a href={b.link_url} target="_blank" rel="noreferrer">{b.link_label || t("Read more")}</a></>}
            </span>
            {b.dismissible && <button className="tool-btn" aria-label={t("Close")} onClick={() => dismiss(b.id)}><X size={16} /></button>}
          </div>
        );
      })}
    </>
  );
}
