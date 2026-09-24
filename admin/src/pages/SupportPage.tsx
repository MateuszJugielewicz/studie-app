import { useEffect, useRef, useState } from "react";
import { ActionButton, Badge, PageState, Search, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { SupportStatus, SupportTicket } from "../lib/types";

type Filter = SupportStatus | "all";

export default function SupportPage() {
  const api = useApi();
  const tickets = useLoad(() => api.supportTickets());
  const [filter, setFilter] = useState<Filter>("open");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // New messages arrive while the page is open.
  useEffect(() => {
    const timer = window.setInterval(() => void tickets.reload(), 30_000);
    return () => window.clearInterval(timer);
  }, [tickets.reload]);

  const all = tickets.data ?? [];
  const count = (s: SupportStatus) => all.filter((t) => t.status === s).length;
  const q = query.trim().toLowerCase();
  const rows = all.filter((t) =>
    (filter === "all" || t.status === filter) &&
    (!q || [t.subject, t.user_name, t.user_email, t.last_message_preview, t.booking_reference ?? ""].some((v) => v.toLowerCase().includes(q))),
  );
  const selected = all.find((t) => t.id === selectedId) ?? null;

  return (
    <>
      <header className="page-header">
        <h1>Support</h1>
        <Search value={query} onChange={setQuery} placeholder="Search name, email, subject…" />
      </header>
      <Tabs<Filter>
        value={filter}
        onChange={setFilter}
        tabs={[
          { id: "open", title: "Needs reply", count: count("open") },
          { id: "answered", title: "Waiting on user", count: count("answered") },
          { id: "closed", title: "Closed" },
          { id: "all", title: "All" },
        ]}
      />
      <PageState loading={tickets.loading && !tickets.data} error={tickets.error}>
        <div className="support">
          <div className="card ticket-list">
            {rows.length === 0 && <div className="muted" style={{ padding: 16 }}>Nothing here.</div>}
            {rows.map((t) => (
              <button key={t.id} className={t.id === selectedId ? "ticket active" : "ticket"} onClick={() => setSelectedId(t.id)}>
                <div className="row between">
                  <strong>{t.subject}</strong>
                  <span className="muted small">{date(t.last_message_at)}</span>
                </div>
                <div className="row gap small">
                  {t.admin_unread > 0 && <span className="unread-dot" aria-label="Unread" />}
                  <span>{t.user_name}</span>
                  <span className="muted">· {label(t.user_role)} · {label(t.category)}</span>
                </div>
                <div className="preview">{t.last_message_preview}</div>
              </button>
            ))}
          </div>
          {selected ? (
            <TicketThread key={selected.id} ticket={selected} onChanged={tickets.reload} />
          ) : (
            <div className="card muted">Select a request to read and reply.</div>
          )}
        </div>
      </PageState>
    </>
  );
}

function TicketThread({ ticket, onChanged }: { ticket: SupportTicket; onChanged: () => Promise<void> }) {
  const api = useApi();
  const messages = useLoad(() => api.supportMessages(ticket.id), [ticket.id, ticket.last_message_at]);
  const [reply, setReply] = useState("");
  const [closeAfter, setCloseAfter] = useState(false);
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (ticket.admin_unread > 0) void api.markSupportRead(ticket.id).then(onChanged);
  }, [ticket.id, ticket.admin_unread]);

  useEffect(() => {
    end.current?.scrollIntoView({ block: "end" });
  }, [messages.data?.length]);

  const send = async () => {
    await api.replyToSupport(ticket.id, reply);
    if (closeAfter) await api.setSupportStatus(ticket.id, "closed");
    setReply("");
    await onChanged();
    await messages.reload();
  };

  return (
    <div className="card">
      <div className="row between">
        <div>
          <h2 style={{ margin: 0 }}>{ticket.subject}</h2>
          <div className="muted small">
            {ticket.user_name} · <a href={`mailto:${ticket.user_email}`}>{ticket.user_email}</a> · {label(ticket.user_role)}
            {ticket.booking_reference && <> · Booking <span className="mono">{ticket.booking_reference}</span></>}
            {" "}· opened {date(ticket.created_at, true)}
          </div>
        </div>
        <Badge value={ticket.status} />
      </div>

      <PageState loading={messages.loading && !messages.data} error={messages.error}>
        <div className="thread" style={{ marginTop: 16 }}>
          {(messages.data ?? []).map((m) => (
            <div key={m.id} className={m.from_admin ? "bubble admin" : "bubble user"}>
              {m.body}
              <div className="bubble-meta">{m.from_admin ? "EasySesh" : ticket.user_name} · {date(m.created_at, true)}</div>
            </div>
          ))}
          <div ref={end} />
        </div>
      </PageState>

      <div className="composer">
        <textarea placeholder={`Reply to ${ticket.user_name}… (they get a push notification)`} value={reply} onChange={(e) => setReply(e.target.value)} maxLength={4000} />
        <div className="row between wrap">
          <label className="row gap small"><input type="checkbox" style={{ width: "auto" }} checked={closeAfter} onChange={(e) => setCloseAfter(e.target.checked)} /> Close after sending</label>
          <div className="row gap">
            {ticket.status === "closed" ? (
              <ActionButton kind="secondary" onClick={async () => { await api.setSupportStatus(ticket.id, "open"); await onChanged(); }}>Reopen</ActionButton>
            ) : (
              <ActionButton kind="secondary" onClick={async () => { await api.setSupportStatus(ticket.id, "closed"); await onChanged(); }}>Close without reply</ActionButton>
            )}
            <ActionButton disabled={!reply.trim()} onClick={send}>Send reply</ActionButton>
          </div>
        </div>
      </div>
    </div>
  );
}
