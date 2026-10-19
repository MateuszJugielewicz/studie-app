// Everything the EasySesh team did to the account – warnings, suspensions, bans and changes – with
// the reasons. Unlike notifications, this can't be deleted, so it can always be read again.
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Ban, Clock3, LifeBuoy, PencilLine, ShieldAlert, TriangleAlert } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import type { AccountChangeNotice, ModerationRecord } from "../lib/types";
import { C, Empty, IconTile, Loading, PageHead, Tiles } from "../components/ui";

type Entry = { kind: "moderation"; at: string; item: ModerationRecord } | { kind: "change"; at: string; item: AccountChangeNotice };

const actionTitle = (m: ModerationRecord) =>
  m.action === "warning" ? "Warning" : m.action === "ban" ? "Account banned" : m.action === "lifted" ? "Restriction lifted"
    : m.studio_id ? "Studio suspended" : "Account suspended";

export default function AccountHistory() {
  const [entries, setEntries] = useState<Entry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.accountHistory().then(({ moderation, changes }) => {
      const all: Entry[] = [
        ...moderation.map((item) => ({ kind: "moderation" as const, at: item.created_at, item })),
        ...changes.map((item) => ({ kind: "change" as const, at: item.created_at, item })),
      ];
      setEntries(all.sort((a, b) => b.at.localeCompare(a.at)));
    }).catch((e) => setError(userMessage(e)));
  }, []);

  return (
    <main className="page narrow">
      <PageHead title="Warnings & account history" />
      <p className="subhead secondary" style={{ margin: "0 4px 12px" }}>{t("Warnings, restrictions and changes the EasySesh team made to your account, with the reasons.")}</p>
      {error ? <div className="card empty">{error}</div> : !entries ? <Loading /> : entries.length === 0 ? (
        <Empty icon={ShieldAlert} title="Nothing here" message="You have no warnings, and the EasySesh team hasn't changed your account." />
      ) : (
        <div className="stack">
          {entries.map((e) => e.kind === "moderation" ? (
            <div key={e.item.id} className="card row top" style={{ gap: 12 }}>
              <IconTile icon={e.item.action === "warning" ? TriangleAlert : e.item.action.includes("lift") ? Clock3 : Ban} size={40}
                colors={e.item.action === "warning" ? [C.warning, C.accent] : e.item.action.includes("lift") ? Tiles.mint : [C.red, C.magenta]} />
              <div className="grow stack" style={{ gap: 4 }}>
                <div className="row" style={{ gap: 8 }}><span className="headline grow">{t(actionTitle(e.item))}</span><span className="caption tertiary">{Dates.abbreviated(e.at)}</span></div>
                {e.item.reason && <div className="body" style={{ whiteSpace: "pre-wrap" }}>{e.item.reason}</div>}
                {e.item.ends_at && <div className="caption secondary">{format("Until %@.", Dates.abbreviatedWithTime(e.item.ends_at))}</div>}
              </div>
            </div>
          ) : (
            <div key={e.item.id} className="card row top" style={{ gap: 12 }}>
              <IconTile icon={PencilLine} size={40} colors={Tiles.signal} />
              <div className="grow stack" style={{ gap: 4 }}>
                <div className="row" style={{ gap: 8 }}><span className="headline grow">{t("Your account was updated")}</span><span className="caption tertiary">{Dates.abbreviated(e.at)}</span></div>
                <ul style={{ margin: 0, paddingLeft: 18 }} className="subhead">{e.item.changes.map((c, i) => <li key={i}>{c}</li>)}</ul>
                {e.item.reason && <div className="subhead secondary">{t("Why:")} {e.item.reason}</div>}
              </div>
            </div>
          ))}
          <Link to="/support" className="btn secondary block"><LifeBuoy size={18} />{t("Disagree? Contact support")}</Link>
        </div>
      )}
    </main>
  );
}
