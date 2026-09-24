import { useState } from "react";
import { ActionButton, Badge, PageState, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { Report, ReportTarget } from "../lib/types";

type Tab = ReportTarget | "reviews";

export default function ModerationPage() {
  const api = useApi();
  const reports = useLoad(() => api.reports());
  const reviews = useLoad(() => api.reviews());
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
          { id: "reviews", title: "All reviews" },
        ]}
      />
      {tab === "reviews" ? (
        <PageState loading={reviews.loading && !reviews.data} error={reviews.error}>
          <div className="card flush">
            <table>
              <thead><tr><th>Date</th><th>Artist</th><th>Rating</th><th>Review</th><th>Visible</th><th></th></tr></thead>
              <tbody>
                {(reviews.data ?? []).map((r) => (
                  <tr key={r.id}>
                    <td>{date(r.created_at)}</td>
                    <td>{r.artist_name}</td>
                    <td>{"★".repeat(r.rating)}</td>
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
          <input placeholder="Internal note" value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="row gap wrap">
            {target?.reviewId && (
              <ActionButton kind="danger" onClick={async () => { await api.setReviewHidden(target.reviewId!, true); await resolve("resolved"); }}>Hide review & resolve</ActionButton>
            )}
            {target?.studioId && (
              <ActionButton kind="danger" confirm="Suspend this studio?" onClick={async () => { await api.setStudioState(target.studioId!, { suspended: true, note: note || "Suspended after a report" }); await resolve("resolved"); }}>Suspend studio</ActionButton>
            )}
            {target?.userId && (
              <ActionButton kind="danger" confirm="Suspend this user?" onClick={async () => { await api.setUserStatus(target.userId!, "suspended", note || `Report: ${report.reason}`); await resolve("resolved"); }}>Suspend user</ActionButton>
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
