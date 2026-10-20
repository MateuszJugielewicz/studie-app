// "Get verified": artists and studios apply for the verified badge; the EasySesh team reviews it.
import { useCallback, useEffect, useState } from "react";
import { BadgeCheck, Clock, Plus, X } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { t } from "../lib/i18n";
import { useApp } from "../lib/state";
import type { VerificationRequest } from "../lib/types";
import { IconTile, InputItem, Item, Section, Sheet, Tiles, ToolButton, useToast } from "../components/ui";

export function VerificationCard({ kind, verified }: { kind: "artist" | "studio"; verified: boolean }) {
  const app = useApp();
  const toast = useToast();
  const [requests, setRequests] = useState<VerificationRequest[]>([]);
  const [applying, setApplying] = useState(false);
  const load = useCallback(() => { if (app.account) api.verificationRequests(app.account.id).then((list) => setRequests(list.filter((r) => r.kind === kind))).catch(() => undefined); }, [app.account, kind]);
  useEffect(() => { load(); }, [load]);
  if (verified) return null;
  const latest = requests.find((r) => r.status !== "cancelled");
  const pending = latest?.status === "pending";
  const denied = latest?.status === "denied";

  return (
    <>
      <div className="card stack" style={{ gap: 10, padding: 14 }}>
        <div className="row top">
          <IconTile icon={pending ? Clock : BadgeCheck} colors={Tiles.blue} />
          <div className="grow">
            <div className="subhead bold">{t(pending ? "Verification requested" : "Get verified")}</div>
            <div className="caption secondary">
              {pending ? t("The EasySesh team is reviewing your application. You'll get a notification when it's decided.")
                : kind === "studio" ? t("Verified studios get a badge on their page. Tell us about your studio and add links so we can confirm it's you.")
                : t("Verified artists get a badge. Link your Spotify or Instagram and our team will verify you.")}
            </div>
            {denied && latest?.staff_note && <div className="caption" style={{ marginTop: 6 }}><b>{t("Last application:")}</b> {latest.staff_note}</div>}
          </div>
        </div>
        {pending ? (
          <button className="btn secondary small" onClick={async () => { try { await api.cancelVerificationRequest(latest!.id); load(); } catch (e) { toast(userMessage(e)); } }}>{t("Cancel application")}</button>
        ) : (
          <button className="btn primary small" onClick={() => setApplying(true)}>{t(denied ? "Apply again" : "Apply for verification")}</button>
        )}
        {latest && <div className="caption2 tertiary">{Dates.abbreviated(latest.created_at)}</div>}
      </div>
      <ApplySheet open={applying} kind={kind} onClose={() => setApplying(false)} onSent={() => { setApplying(false); load(); toast(t("Application sent."), "info"); }} />
    </>
  );
}

function ApplySheet({ open, kind, onClose, onSent }: { open: boolean; kind: "artist" | "studio"; onClose: () => void; onSent: () => void }) {
  const toast = useToast();
  const [message, setMessage] = useState("");
  const [links, setLinks] = useState<string[]>([""]);
  const [sending, setSending] = useState(false);
  const valid = message.trim().length >= 10;
  async function send() {
    setSending(true);
    try { await api.requestVerification(message.trim(), links.map((l) => l.trim()).filter(Boolean)); setMessage(""); setLinks([""]); onSent(); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={open} onClose={onClose} title="Apply for verification" closeLabel="Cancel"
      actions={<ToolButton title={sending ? "Sending…" : "Send"} bold disabled={!valid || sending} onClick={send} />}>
      <div className="stack-lg">
        <Section header={kind === "studio" ? "About your studio" : "About you"} footer="At least 10 characters. Tell us who you are and why you should be verified.">
          <Item><textarea rows={5} value={message} onChange={(e) => setMessage(e.target.value.slice(0, 2000))}
            placeholder={t(kind === "studio" ? "e.g. We're a recording studio in Athens since 2015, with 300 sessions a year." : "e.g. I release music on Spotify and play live in Athens.")} /></Item>
        </Section>
        <Section header="Links" footer="Spotify, Instagram, YouTube, your website… so we can confirm it's you.">
          {links.map((link, i) => (
            <div key={i} className="row" style={{ gap: 6 }}>
              <div className="grow"><InputItem placeholder="https://" value={link} onChange={(v) => setLinks(links.map((l, j) => (j === i ? v.slice(0, 300) : l)))} /></div>
              {links.length > 1 && <button className="icon-btn" aria-label={t("Remove")} onClick={() => setLinks(links.filter((_, j) => j !== i))}><X size={16} /></button>}
            </div>
          ))}
          {links.length < 6 && <Item onClick={() => setLinks([...links, ""])}><Plus size={16} color="var(--accent)" /><span className="label accent">{t("Add link")}</span></Item>}
        </Section>
        <button className="btn primary block" disabled={!valid || sending} onClick={send}>{t(sending ? "Sending…" : "Send application")}</button>
      </div>
    </Sheet>
  );
}
