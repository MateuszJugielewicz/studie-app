import { useState, type ReactNode } from "react";
import { ActionButton, Badge, Modal, PageState, Search, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, money } from "../lib/format";
import type { Studio } from "../lib/types";

type Tab = "applications" | "approved" | "changes" | "rejected" | "suspended" | "all";
const weekdays = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const hhmm = (m: number) => `${String(Math.floor((m % 1440) / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

export default function StudiosPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.studios());
  const [tab, setTab] = useState<Tab>("applications");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Studio | null>(null);

  const studios = data ?? [];
  const filters: Record<Tab, (s: Studio) => boolean> = {
    applications: (s) => s.status === "pending_review",
    approved: (s) => s.status === "approved",
    changes: (s) => s.status === "changes_requested",
    rejected: (s) => s.status === "rejected",
    suspended: (s) => s.status === "suspended",
    all: () => true,
  };
  const q = query.toLowerCase();
  const rows = studios.filter(filters[tab]).filter((s) => !q || `${s.name} ${s.address.city} ${s.address.area} ${s.contact.email}`.toLowerCase().includes(q));

  return (
    <>
      <header className="page-header">
        <h1>Studios</h1>
        <Search value={query} onChange={setQuery} placeholder="Search name, city, email…" />
      </header>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "applications", title: "New applications", count: studios.filter(filters.applications).length },
          { id: "approved", title: "Approved", count: studios.filter(filters.approved).length },
          { id: "changes", title: "Changes requested", count: studios.filter(filters.changes).length },
          { id: "rejected", title: "Rejected", count: studios.filter(filters.rejected).length },
          { id: "suspended", title: "Suspended", count: studios.filter(filters.suspended).length },
          { id: "all", title: "All" },
        ]}
      />
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table className="clickable">
            <thead><tr><th>Studio</th><th>Area</th><th>From</th><th>Status</th><th>Live</th><th>Rating</th><th>Bookings</th><th>Submitted</th></tr></thead>
            <tbody>
              {rows.map((s) => (
                <tr key={s.id} onClick={() => setSelected(s)}>
                  <td>
                    <div className="row">
                      <img className="thumb" src={s.photo_urls[0]} alt="" />
                      <div><div className="strong">{s.name} {s.is_verified && <span title="Verified">✔︎</span>}</div><div className="muted small">{s.contact.email}</div></div>
                    </div>
                  </td>
                  <td>{s.address.area}, {s.address.city}</td>
                  <td>{money(s.price_from, s.currency)}/h</td>
                  <td><Badge value={s.status} /></td>
                  <td>{s.is_active ? "🟢" : "⚪️"}</td>
                  <td>{s.review_count ? `★ ${s.rating_average.toFixed(1)} (${s.review_count})` : "–"}</td>
                  <td>{s.booking_count}</td>
                  <td>{date(s.submitted_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
      {selected && (
        <StudioModal
          studio={selected}
          onClose={() => setSelected(null)}
          onChanged={async () => {
            await reload();
            setSelected(null);
          }}
        />
      )}
    </>
  );
}

function StudioModal({ studio, onClose, onChanged }: { studio: Studio; onClose: () => void; onChanged: () => Promise<void> }) {
  const api = useApi();
  const { data: events } = useLoad(() => api.studioEvents(studio.id), [studio.id]);
  const [note, setNote] = useState(studio.admin_note ?? "");
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState({ name: studio.name, tagline: studio.tagline, description: studio.description, capacity: studio.capacity });

  const decide = (decision: "approve" | "reject" | "request_changes") => async () => {
    await api.reviewStudio(studio.id, decision, note.trim() || undefined);
    await onChanged();
  };

  return (
    <Modal
      title={studio.name}
      onClose={onClose}
      footer={
        <>
          {(studio.status === "pending_review" || studio.status === "changes_requested" || studio.status === "rejected") && (
            <>
              <ActionButton onClick={decide("approve")}>✅ Approve</ActionButton>
              <ActionButton kind="secondary" onClick={decide("request_changes")} disabled={!note.trim()}>✏️ Request changes</ActionButton>
              <ActionButton kind="danger" onClick={decide("reject")} disabled={!note.trim()} confirm="Reject this studio?">✖ Reject</ActionButton>
            </>
          )}
          {studio.status === "approved" && (
            <>
              <ActionButton kind="secondary" onClick={async () => { await api.setStudioState(studio.id, { active: !studio.is_active }); await onChanged(); }}>
                {studio.is_active ? "Mark inactive" : "Mark active"}
              </ActionButton>
              <ActionButton kind="danger" confirm="Suspend this studio? It will be hidden from artists." onClick={async () => { await api.setStudioState(studio.id, { suspended: true, note: note || undefined }); await onChanged(); }}>
                Suspend
              </ActionButton>
            </>
          )}
          {studio.status === "suspended" && (
            <ActionButton kind="secondary" onClick={async () => { await api.setStudioState(studio.id, { suspended: false }); await onChanged(); }}>Lift suspension</ActionButton>
          )}
          <ActionButton kind="secondary" onClick={async () => { await api.setStudioState(studio.id, { verified: !studio.is_verified }); await onChanged(); }}>
            {studio.is_verified ? "Remove verification" : "Verify studio"}
          </ActionButton>
        </>
      }
    >
      <div className="row gap">
        <Badge value={studio.status} />
        {studio.is_active && <Badge value="active" text="Live" />}
        {studio.is_verified && <Badge value="approved" text="Verified" />}
      </div>

      <div className="photos">
        {studio.photo_urls.map((url) => <a key={url} href={url} target="_blank" rel="noreferrer"><img src={url} alt="" /></a>)}
        {studio.video_url && <a className="video-link" href={studio.video_url} target="_blank" rel="noreferrer">▶ Video</a>}
      </div>

      {editing ? (
        <div className="form">
          <label>Name<input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} /></label>
          <label>Tagline<input value={draft.tagline} onChange={(e) => setDraft({ ...draft, tagline: e.target.value })} /></label>
          <label>Description<textarea rows={5} value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} /></label>
          <label>Capacity<input type="number" value={draft.capacity} onChange={(e) => setDraft({ ...draft, capacity: Number(e.target.value) })} /></label>
          <div className="row gap">
            <ActionButton onClick={async () => { await api.updateStudio(studio.id, draft); await onChanged(); }}>Save changes</ActionButton>
            <button className="secondary" onClick={() => setEditing(false)}>Cancel</button>
          </div>
        </div>
      ) : (
        <>
          <p className="strong">{studio.tagline}</p>
          <p>{studio.description}</p>
          <button className="ghost small" onClick={() => setEditing(true)}>✏️ Edit listing</button>
        </>
      )}

      <div className="details">
        <Detail title="Address">{studio.address.street}, {studio.address.postal_code} {studio.address.city} ({studio.address.area}), {studio.address.country}<br /><span className="muted small">{studio.latitude.toFixed(4)}, {studio.longitude.toFixed(4)}</span></Detail>
        <Detail title="Contact">{studio.contact.email}<br />{studio.contact.phone}<br />{studio.contact.website}</Detail>
        <Detail title="Prices">
          {studio.session_types.map((t) => <div key={t.id}>{t.name}: {money(t.hourly_rate, studio.currency)}/h (min {t.minimum_hours}h){t.includes_engineer ? " · engineer" : ""}</div>)}
          {studio.add_ons.map((a) => <div key={a.id} className="muted">{a.name}: {money(a.price, studio.currency)} {label(a.unit)}</div>)}
        </Detail>
        <Detail title="Booking terms">
          {studio.booking_policy.instant_book ? "Instant book" : "Request to book"} · {label(studio.booking_policy.cancellation_policy ?? "moderate")} cancellation
          {studio.booking_policy.deposit_percent ? ` · ${studio.booking_policy.deposit_percent}% deposit` : ""}
          {studio.booking_policy.terms && <div className="muted small">{studio.booking_policy.terms}</div>}
        </Detail>
        <Detail title="Opening hours">
          {studio.opening_hours.slice().sort((a, b) => ((a.weekday + 5) % 7) - ((b.weekday + 5) % 7)).map((h) => (
            <div key={h.weekday}>{weekdays[h.weekday]}: {h.is_closed ? "Closed" : `${hhmm(h.opens_at)}–${hhmm(h.closes_at)}`}</div>
          ))}
        </Detail>
        <Detail title="Equipment">{studio.equipment.map((e) => <div key={e.id}>{e.name} <span className="muted small">{label(e.category)}</span></div>)}</Detail>
        <Detail title="Facilities">{studio.facilities.map(label).join(", ") || "–"}</Detail>
        <Detail title="Genres">{studio.genres.map(label).join(", ") || "–"}</Detail>
        <Detail title="Capacity">{studio.capacity} people</Detail>
        <Detail title="Engineers / producers">{studio.engineers.map((e) => `${e.name} (${e.role})`).join(", ") || "–"}</Detail>
        <Detail title="Rules">{studio.rules.join(" · ") || "–"}</Detail>
      </div>

      <label className="form">
        Note to studio (required to reject or request changes)
        <textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Please add photos of the vocal booth and list your microphones." />
      </label>

      <h3>History</h3>
      <ul className="timeline">
        {(events ?? []).map((e) => (
          <li key={e.id}>
            <span className="muted small">{date(e.created_at, true)}</span> {e.from_status ? `${label(e.from_status)} → ` : ""}<strong>{label(e.to_status)}</strong>
            {e.note && <div className="muted small">“{e.note}”</div>}
          </li>
        ))}
      </ul>
    </Modal>
  );
}

function Detail({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="detail">
      <div className="muted small">{title}</div>
      <div>{children}</div>
    </div>
  );
}
