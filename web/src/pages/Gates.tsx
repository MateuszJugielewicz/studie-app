// Things that pop up over any page, like in the apps: accepting new terms, warnings from the team,
// "What's new" and choosing a new password after a reset link.
import { useState } from "react";
import { CheckCircle2, ChevronRight, Hand, Sparkles, TriangleAlert, Users } from "lucide-react";
import { useApp } from "../lib/state";
import { t } from "../lib/i18n";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { IconTile, Logo, Sheet, Tiles, Toggle, ToolButton, useToast } from "../components/ui";
import { LEGAL, LegalDocumentBody, requiredDocuments, type LegalDocument } from "./Legal";
import { ChangePasswordForm } from "./Settings";
import type { ChangelogEntry } from "../lib/types";

export function GlobalSheets() {
  const app = useApp();
  if (!app.account) return app.needsNewPassword ? <RecoverySheet /> : null;
  if (app.needsNewPassword) return <RecoverySheet />;
  if (app.needsTermsAcceptance) return <TermsAcceptance />;
  if (app.warnings[0]) return <WarningSheet />;
  if (app.account.role !== "admin" && app.unseenChangelog.length) return <WhatsNew entries={app.unseenChangelog} onClose={app.markChangelogSeen} />;
  return null;
}

function RecoverySheet() {
  const app = useApp();
  return (
    <Sheet open onClose={() => app.setNeedsNewPassword(false)} title="Change password" closeLabel="Later">
      <ChangePasswordForm isRecovery onDone={() => app.setNeedsNewPassword(false)} />
    </Sheet>
  );
}

/**
 * Shown when the signed-in user hasn't accepted the current terms (new account via Google/Apple,
 * or after a legal update). Every document has to be opened before the user can accept.
 */
function TermsAcceptance() {
  const app = useApp();
  const toast = useToast();
  const [opened, setOpened] = useState<string[]>([]);
  const [reading, setReading] = useState<LegalDocument | null>(null);
  const [agreed, setAgreed] = useState(false);
  const [saving, setSaving] = useState(false);
  const documents = requiredDocuments(app.account!.role);
  const isUpdate = !!app.account!.accepted_terms_version;
  const allRead = documents.every((d) => opened.includes(d));

  async function accept() {
    setSaving(true);
    try { app.setAccount(await api.acceptTerms(app.requiredTermsVersion)); } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }

  if (reading) {
    return (
      <Sheet open onClose={() => setReading(null)} title={reading.title} closeLabel="Done">
        <LegalDocumentBody doc={reading} />
      </Sheet>
    );
  }
  return (
    <Sheet open onClose={() => undefined} closeLabel="Sign out" title="">
      <div className="stack" style={{ paddingTop: 4 }}>
        <div className="row spread"><Logo size={22} /><ToolButton title="Sign out" onClick={() => app.signOut()} /></div>
        <h2 className="title-l">{t(isUpdate ? "We've updated our terms" : "Before you start")}</h2>
        <p className="secondary" style={{ margin: 0 }}>{t(isUpdate ? "Please read the updated documents again and accept them to keep using EasySesh." : "Please read and accept the documents below to use EasySesh.")}</p>
        {app.pendingLegalUpdate && (
          <div className="card">
            <div className="row caption heavy accent" style={{ gap: 6 }}><Sparkles size={14} />{t("What changed").toUpperCase()}</div>
            <div className="headline" style={{ marginTop: 6 }}>{t(app.pendingLegalUpdate.title)}</div>
            {app.pendingLegalUpdate.body && <div className="subhead secondary pre">{app.pendingLegalUpdate.body}</div>}
          </div>
        )}
        <div className="card tight">
          {documents.map((key, i) => {
            const doc = LEGAL[key];
            const read = opened.includes(key);
            return (
              <button key={key} className="row" style={{ width: "100%", padding: "10px 4px", borderTop: i ? "0.5px solid var(--stroke)" : undefined, textAlign: "left" }}
                onClick={() => { setOpened((o) => [...new Set([...o, key])]); setReading(doc); }}>
                <IconTile icon={doc.icon} colors={read ? Tiles.mint : Tiles.violet} />
                <span className="grow"><div className="subhead semibold">{t(doc.title)}</div><div className="caption secondary">{t(read ? "Read" : "Tap to read")}</div></span>
                {read ? <CheckCircle2 color="var(--positive)" /> : <ChevronRight className="secondary" />}
              </button>
            );
          })}
        </div>
        <div className="card tight row">
          <span className="grow subhead semibold" style={{ color: allRead ? undefined : "var(--text-2)" }}>{t("I have read and accept these documents")}</span>
          <Toggle checked={agreed} onChange={setAgreed} disabled={!allRead} />
        </div>
        {!allRead && <div className="row caption secondary" style={{ gap: 6 }}><Hand size={14} />{t("Open each document to continue.")}</div>}
        <button className="btn primary block" disabled={!agreed || !allRead || saving} onClick={accept}>{t(saving ? "Saving…" : "Accept and continue")}</button>
        <div className="caption tertiary">{t("We record the version and time of your acceptance. You can withdraw consent by deleting your account in Settings.")}</div>
      </div>
    </Sheet>
  );
}

/** A warning from the EasySesh team. It stays until the user confirms they've read it. */
function WarningSheet() {
  const app = useApp();
  const warning = app.warnings[0];
  const [saving, setSaving] = useState(false);
  const [reading, setReading] = useState(false);
  if (reading) {
    return <Sheet open onClose={() => setReading(false)} title={LEGAL.community.title} closeLabel="Done"><LegalDocumentBody doc={LEGAL.community} /></Sheet>;
  }
  return (
    <Sheet open onClose={() => undefined} title="">
      <div className="stack">
        <div className="row">
          <IconTile icon={TriangleAlert} size={48} />
          <div><div className="title-m heavy">{t("Warning from EasySesh")}</div><div className="caption secondary">{Dates.abbreviatedWithTime(warning.created_at)}</div></div>
        </div>
        <div className="card pre">{warning.reason}</div>
        <div className="subhead secondary">{t("Please follow our Community Guidelines. Further breaches can lead to your account being suspended or banned.")}</div>
        <button className="row link-btn" onClick={() => setReading(true)}><Users size={18} />{t("Read the Community Guidelines")}</button>
        <button className="btn primary block" disabled={saving} onClick={async () => { setSaving(true); await app.acknowledgeWarning(warning); setSaving(false); }}>{t("I understand")}</button>
      </div>
    </Sheet>
  );
}

export function ChangelogCard({ entry }: { entry: ChangelogEntry }) {
  return (
    <div className="card">
      <div className="row" style={{ gap: 8 }}>
        <span className="caption heavy accent">{entry.version}</span>
        {entry.is_legal_update && <span className="pill" style={{ background: "color-mix(in srgb, var(--violet) 15%, transparent)", color: "var(--violet)" }}>{t("Legal update")}</span>}
        <span className="grow" />
        <span className="caption2 tertiary">{Dates.abbreviated(entry.published_at)}</span>
      </div>
      <div className="headline" style={{ marginTop: 6 }}>{entry.title}</div>
      {entry.body && <div className="subhead secondary pre" style={{ marginTop: 4 }}>{entry.body}</div>}
    </div>
  );
}

/** "What's new": update notes from the EasySesh team, shown once after they're published. */
function WhatsNew({ entries, onClose }: { entries: ChangelogEntry[]; onClose: () => void }) {
  return (
    <Sheet open onClose={onClose} title="">
      <div className="stack">
        <div className="row"><IconTile icon={Sparkles} size={44} colors={Tiles.violet} /><h2 className="title-l">{t("What's new")}</h2></div>
        {entries.map((e) => <ChangelogCard key={e.id} entry={e} />)}
        <button className="btn primary block" onClick={onClose}>{t("Got it")}</button>
      </div>
    </Sheet>
  );
}
