import { useState } from "react";
import { ActionButton, Badge, Modal, PageState, Search, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, money } from "../lib/format";
import type { Booking, BookingStatus, Dispute } from "../lib/types";

type Tab = "all" | "active" | "completed" | "cancelled" | "refunds" | "disputes";

export default function BookingsPage() {
  const api = useApi();
  const bookings = useLoad(() => api.bookings());
  const disputes = useLoad(() => api.disputes());
  const [tab, setTab] = useState<Tab>("all");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Booking | null>(null);

  const all = bookings.data ?? [];
  const openDisputes = (disputes.data ?? []).filter((d) => d.status === "open");
  const filters: Record<Tab, (b: Booking) => boolean> = {
    all: () => true,
    active: (b) => ["pending_approval", "confirmed"].includes(b.status),
    completed: (b) => b.status === "completed",
    cancelled: (b) => ["cancelled", "declined", "expired"].includes(b.status),
    refunds: (b) => b.refund_amount > 0,
    disputes: (b) => b.status === "disputed" || (disputes.data ?? []).some((d) => d.booking_id === b.id),
  };
  const q = query.toLowerCase();
  const rows = all.filter(filters[tab]).filter((b) => !q || `${b.reference} ${b.artist_name} ${b.studio_name}`.toLowerCase().includes(q));

  const reload = async () => {
    await Promise.all([bookings.reload(), disputes.reload()]);
  };

  return (
    <>
      <header className="page-header">
        <h1>Bookings</h1>
        <Search value={query} onChange={setQuery} placeholder="Reference, artist, studio…" />
      </header>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "all", title: "All", count: all.length },
          { id: "active", title: "Active", count: all.filter(filters.active).length },
          { id: "completed", title: "Completed", count: all.filter(filters.completed).length },
          { id: "cancelled", title: "Cancelled", count: all.filter(filters.cancelled).length },
          { id: "refunds", title: "Refunds", count: all.filter(filters.refunds).length },
          { id: "disputes", title: "Problems / disputes", count: openDisputes.length },
        ]}
      />
      <PageState loading={bookings.loading && !bookings.data} error={bookings.error} empty={rows.length === 0}>
        <div className="card flush">
          <table className="clickable">
            <thead><tr><th>Ref</th><th>Artist</th><th>Studio</th><th>Session</th><th>Status</th><th>Payment</th><th>Total</th><th>Refunded</th></tr></thead>
            <tbody>
              {rows.map((b) => (
                <tr key={b.id} onClick={() => setSelected(b)}>
                  <td className="mono">{b.reference}</td>
                  <td>{b.artist_name}</td>
                  <td>{b.studio_name}</td>
                  <td>{date(b.starts_at, true)} · {b.hours}h</td>
                  <td><Badge value={b.status} /></td>
                  <td><Badge value={b.payment_status} />{b.payment_method === "cash" && <span className="muted small"> · cash</span>}</td>
                  <td>{money(b.price.total, b.price.currency)}</td>
                  <td>{b.refund_amount ? money(b.refund_amount, b.price.currency) : "–"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
      {selected && (
        <BookingModal
          booking={selected}
          dispute={(disputes.data ?? []).find((d) => d.booking_id === selected.id && d.status === "open")}
          onClose={() => setSelected(null)}
          onChanged={async () => { await reload(); setSelected(null); }}
        />
      )}
    </>
  );
}

function BookingModal({ booking, dispute, onClose, onChanged }: { booking: Booking; dispute?: Dispute; onClose: () => void; onChanged: () => Promise<void> }) {
  const api = useApi();
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [resolution, setResolution] = useState("");
  const [outcome, setOutcome] = useState<BookingStatus>("completed");
  const p = booking.price;

  return (
    <Modal title={`Booking ${booking.reference}`} onClose={onClose}>
      <div className="row gap"><Badge value={booking.status} /><Badge value={booking.payment_status} /></div>
      <div className="details">
        <div className="detail"><div className="muted small">Artist</div>{booking.artist_name}</div>
        <div className="detail"><div className="muted small">Studio</div>{booking.studio_name}</div>
        <div className="detail"><div className="muted small">Session</div>{booking.session_type_name} · {booking.hours}h<br />{date(booking.starts_at, true)} – {date(booking.ends_at, true)}</div>
        <div className="detail"><div className="muted small">Created</div>{date(booking.created_at, true)}</div>
        {booking.cancellation_reason && <div className="detail"><div className="muted small">Cancellation ({label(booking.cancelled_by ?? "")})</div>{booking.cancellation_reason}</div>}
        {booking.notes && <div className="detail"><div className="muted small">Notes</div>{booking.notes}</div>}
      </div>
      <table>
        <tbody>
          <tr><td>Subtotal (studio price)</td><td>{money(p.subtotal, p.currency)}</td></tr>
          <tr><td>Payment method</td><td>{label(booking.payment_method ?? "card")}</td></tr>
          <tr><td className="strong">Total paid by artist</td><td className="strong">{money(p.total, p.currency)}</td></tr>
          <tr><td>Sonora platform fee (10%)</td><td>{money(p.studio_commission, p.currency)}</td></tr>
          <tr><td>Studio payout</td><td>{money(p.studio_payout, p.currency)}</td></tr>
          <tr><td>Refunded</td><td>{money(booking.refund_amount, p.currency)}</td></tr>
        </tbody>
      </table>

      {dispute && (
        <div className="card warning">
          <h3>Open dispute</h3>
          <p>“{dispute.reason}”</p>
          <p className="muted small">Opened {date(dispute.created_at, true)}</p>
          <label className="form">Resolution<textarea rows={2} value={resolution} onChange={(e) => setResolution(e.target.value)} placeholder="What was decided and communicated to both parties" /></label>
          <label className="form">Booking outcome
            <select value={outcome} onChange={(e) => setOutcome(e.target.value as BookingStatus)}>
              <option value="completed">Completed (studio is paid)</option>
              <option value="cancelled">Cancelled (no payout)</option>
            </select>
          </label>
          <ActionButton disabled={!resolution.trim()} onClick={async () => { await api.resolveDispute(dispute.id, resolution, outcome); await onChanged(); }}>Resolve dispute</ActionButton>
        </div>
      )}

      {["paid", "deposit_paid", "partially_refunded"].includes(booking.payment_status) && (
        <div className="card">
          <h3>Refund</h3>
          <div className="row gap">
            <input placeholder={`Amount in ${p.currency} (empty = everything)`} value={amount} onChange={(e) => setAmount(e.target.value)} />
            <input placeholder="Reason" value={reason} onChange={(e) => setReason(e.target.value)} />
            <ActionButton
              kind="danger"
              confirm="Issue this refund to the artist's card?"
              onClick={async () => {
                const minor = amount.trim() ? Math.round(Number(amount.replace(",", ".")) * 100) : undefined;
                await api.refund(booking.id, minor, reason || "Admin refund");
                await onChanged();
              }}
            >
              Refund
            </ActionButton>
          </div>
        </div>
      )}
    </Modal>
  );
}
