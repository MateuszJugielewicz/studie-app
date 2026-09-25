import { useState } from "react";
import { ActionButton, Badge, PageState, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { RatingDispute, Report, ReportTarget } from "../lib/types";

type Tab = ReportTarget | "reviews" | "disputes";

export default function ModerationPage() {
  const api = useApi();
  const reports = useLoad(() => api.reports());
  const reviews = useLoad(() => api.reviews());
  const disputes = useLoad(() => api.ratingDisputes());
  const [tab, setTab] = useState<Tab>("review");
  const [showClosed, setShowClosed] = useState(false);

  const all = reports.data ?? [];
  const count = (t: ReportTarget) => all.filter((r) => r.target_type === t && r.status === "open").length;
  const rows = all.filter((r) => r.target_type === tab && (showClosed || r.status === "open"));

  return (
    <>
      <header className="page-header">
        <h1>Moderation</h1>
        <label className="row gap small"><input type="checkbox" checked={showClosed} onChange={(e) => setShowClosed(e.target.checked)} /> Show resolved</label>
      </header>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "user", title: "Reported users", count: count("user") },
          { id: "review", title: "Reported reviews", count: count("review") },
          { id: "studio", title: "Reported studios", count: count("studio") },
          { id: "message", title: "Chat reports", count: count("message") },
          { id: "booking", title: "Booking reports", count: count("booking") },
          { id: "disputes", title: "Rating disputes", count: (disputes.data ?? []).filter((d) => d.status === "open").length },
          { id: "reviews", title: "All reviews" },
        ]}
      />
      {tab === "disputes" ? (
        <PageState loading={disputes.loading && !disputes.data} error={disputes.error} empty={(disputes.data ?? []).filter((d) => showClosed || d.status === "open").length === 0}>
          <div className="stack">
            {(disputes.data ?? []).filter((d) => showClosed || d.status === "open").map((d) => (
              <DisputeCard key={d.id} dispute={d} onChanged={async () => { await disputes.reload(); await reviews.reload(); }} />
            ))}
          </div>
        </PageState>
      ) : tab === "reviews" ? (
        <PageState loading={reviews.loading && !reviews.data} error={reviews.error}>
          <div className="card flush">
            <table>
              <thead><tr><th>Date</th><th>Artist</th><th>Rating</th><th>Review</th><th>Visible</th><th></th></tr></thead>
              <tbody>
                {(reviews.data ?? []).map((r) => (
                  <tr key={r.id}>
                    <td>{date(r.created_at)}</td>
                    <td>{r.artist_name}</td>
                    <td>{r.rating}/5</td>
                    <td>{r.text}{r.studio_reply && <div className="muted small">↳ {r.studio_reply}</div>}</td>
                    <td>{r.is_hidden ? "Hidden" : "Visible"}</td>
                    <td><ActionButton kind="secondary" onClick={async () => { await api.setReviewHidden(r.id, !r.is_hidden); await reviews.reload(); }}>{r.is_hidden ? "Show" : "Hide"}</ActionButton></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </PageState>
      ) : (
        <PageState loading={reports.loading && !reports.data} error={reports.error} empty={rows.length === 0}>
          <div className="stack">
            {rows.map((r) => <ReportCard key={r.id} report={r} onChanged={async () => { await reports.reload(); await reviews.reload(); }} />)}
          </div>
        </PageState>
      )}
    </>
  );
}

function ReportCard({ report, onChanged }: { report: Report; onChanged: () => Promise<void> }) {
  const api = useApi();
  const { data: target } = useLoad(() => api.reportTarget(report), [report.id]);
  const [note, setNote] = useState(report.admin_note ?? "");

  const resolve = async (status: "resolved" | "dismissed") => {
    await api.resolveReport(report.id, status, note || undefined);
    await onChanged();
  };

  return (
    <div className="card">
      <div className="row between">
        <div className="row gap"><Badge value={report.status} /><strong>{label(report.reason)}</strong><span className="muted small">{date(report.created_at, true)}</span></div>
        <span className="muted small">{label(report.target_type)}</span>
      </div>
      <p className="strong">{target?.title ?? "…"}</p>
      {target?.body && <blockquote>{target.body}</blockquote>}
      {report.details && <p className="muted">Reporter: “{report.details}”</p>}
      {report.status === "open" ? (
        <>
          <input placeholder="Note (sent to the user when you warn them)" value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="row gap wrap">
            {target?.reviewId && (
              <ActionButton kind="danger" onClick={async () => { await api.setReviewHidden(target.reviewId!, true); await resolve("resolved"); }}>Hide review & resolve</ActionButton>
            )}
            {target?.userId && (
              <ActionButton kind="secondary" disabled={!note.trim()} onClick={async () => { await api.warnUser(target.userId!, note.trim(), target.studioId); await resolve("resolved"); }}>Warn (note is sent)</ActionButton>
            )}
            {target?.studioId && (
              <ActionButton kind="danger" confirm="Hide this studio for 7 days?" onClick={async () => { await api.moderateStudio(target.studioId!, "suspend", 7, note || "Suspended after a report"); await resolve("resolved"); }}>Suspend studio 7 days</ActionButton>
            )}
            {target?.userId && (
              <ActionButton kind="danger" confirm="Suspend this user for 7 days?" onClick={async () => { await api.moderateUser(target.userId!, "suspend", 7, note || `Report: ${report.reason}`); await resolve("resolved"); }}>Suspend user 7 days</ActionButton>
            )}
            <ActionButton kind="secondary" onClick={() => resolve("resolved")}>Mark resolved</ActionButton>
            <ActionButton kind="secondary" onClick={() => resolve("dismissed")}>Dismiss</ActionButton>
          </div>
        </>
      ) : (
        report.admin_note && <p className="muted small">Admin note: {report.admin_note}</p>
      )}
    </div>
  );
}

function DisputeCard({ dispute, onChanged }: { dispute: RatingDispute; onChanged: () => Promise<void> }) {
  const api = useApi();
  const [note, setNote] = useState(dispute.admin_note ?? "");
  const resolve = (remove: boolean) => async () => {
    await api.resolveRatingDispute(dispute.id, remove, note || undefined);
    await onChanged();
  };
  return (
    <div className="card">
      <div className="row between">
        <div className="row gap">
          <Badge value={dispute.status === "open" ? "open" : dispute.status === "removed" ? "resolved" : "dismissed"} text={label(dispute.status)} />
          <strong>{dispute.review_type === "studio_review" ? "Artist's review of a studio" : "Studio's rating of an artist"}</strong>
          <span className="muted small">{date(dispute.created_at, true)}</span>
        </div>
      </div>
      <p><span className="strong">{dispute.reviewer_name}</span> rated <span className="strong">{dispute.rated_name}</span> {dispute.rating ?? "–"}/5</p>
      {dispute.review_text && <blockquote>{dispute.review_text}</blockquote>}
      <p className="muted">Why it's disputed: “{dispute.reason}”</p>
      {dispute.status === "open" ? (
        <>
          <input placeholder="Note (sent to the person who disputed)" value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="row gap wrap">
            <ActionButton kind="danger" confirm="Remove this rating? It no longer counts towards the average." onClick={resolve(true)}>Remove rating</ActionButton>
            <ActionButton kind="secondary" onClick={resolve(false)}>Keep rating</ActionButton>
          </div>
        </>
      ) : (
        dispute.admin_note && <p className="muted small">Admin note: {dispute.admin_note}</p>
      )}
    </div>
  );
}
