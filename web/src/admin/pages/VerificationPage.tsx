import { useState } from "react";
import { ActionButton, Badge, PageState, Tabs, ViewAsButton } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, safeUrl } from "../lib/format";
import type { VerificationRequest } from "../lib/types";

type Tab = "pending" | "done";

/** Artists' and studios' applications for the verified badge. Anyone on the team (support and up) can decide;
 *  the applicant is notified, with the note. A note is required to deny. */
export default function VerificationPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.verificationRequests());
  const [tab, setTab] = useState<Tab>("pending");
  const all = data ?? [];
  const pending = all.filter((r) => r.status === "pending");
  const rows = tab === "pending" ? pending : all.filter((r) => r.status !== "pending");
  return (
    <>
      <header className="page-header"><h1>Verification</h1></header>
      <p className="muted">Artists and studios apply for the verified badge with a short message and links (Spotify, Instagram, website…). Check that they are who they say they are, then grant or deny. The applicant gets a notification with your note.</p>
      <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: "pending", title: "Waiting", count: pending.length }, { id: "done", title: "Handled" }]} />
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="stack">
          {rows.map((r) => <RequestCard key={r.id} request={r} onDone={reload} />)}
        </div>
      </PageState>
    </>
  );
}

function RequestCard({ request: r, onDone }: { request: VerificationRequest; onDone: () => Promise<void> }) {
  const api = useApi();
  const [note, setNote] = useState("");
  const city = r.kind === "studio" ? r.studio_city : r.artist_city;
  return (
    <div className="card form">
      <div className="row gap wrap">
        {r.photo_url && <img src={r.photo_url} alt="" width={48} height={48} style={{ borderRadius: 12, objectFit: "cover" }} />}
        <div style={{ flex: 1, minWidth: 200 }}>
          <div className="strong">{r.display_name || r.email} <span className="muted small">· {label(r.kind)}</span></div>
          <div className="muted small">{[r.email, city, `${r.booking_count} bookings`, `applied ${date(r.created_at, true)}`].filter(Boolean).join(" · ")}</div>
        </div>
        <Badge value={r.status} />
      </div>
      <div style={{ whiteSpace: "pre-wrap" }}>{r.message}</div>
      {r.links.length > 0 && (
        <div className="row gap wrap">
          {r.links.map((l) => { const url = safeUrl(/^https?:\/\//i.test(l) ? l : `https://${l}`); return url ? <a key={l} href={url} target="_blank" rel="noreferrer noopener">{l}</a> : <span key={l}>{l}</span>; })}
        </div>
      )}
      {r.status === "pending" ? (
        <>
          <label>Note to the applicant (required to deny)<textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Please add a link to your Instagram so we can confirm it's you." /></label>
          <div className="row gap wrap">
            <ActionButton confirm={`Give ${r.display_name || r.email} the verified badge?`} onClick={async () => { await api.reviewVerification(r.id, true, note); await onDone(); }}>Grant verification</ActionButton>
            <ActionButton kind="danger" disabled={!note.trim()} onClick={async () => { await api.reviewVerification(r.id, false, note); await onDone(); }}>Deny</ActionButton>
            <ViewAsButton userId={r.user_id} />
          </div>
        </>
      ) : (
        <div className="muted small">{r.status === "cancelled" ? "Cancelled by the applicant" : `${label(r.status)} by ${r.reviewed_by_email ?? "the team"} · ${date(r.reviewed_at, true)}`}{r.staff_note ? ` – “${r.staff_note}”` : ""}</div>
      )}
    </div>
  );
}
