import { useEffect, useRef, useState } from "react";
import { Route, Routes, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  Archive, ArrowUp, Bug, CalendarDays, CheckCircle2, CircleHelp, CreditCard, FileText, MessageCircleQuestion, MessagesSquare, Mic, PlusCircle, Star, Undo2, UserRound,
  type LucideIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp, useLoad } from "../lib/state";
import { SUPPORT_CATEGORIES, SUPPORT_STATUS_TITLE, type Booking, type SupportCategory, type SupportMessage, type SupportStatus, type SupportTicket } from "../lib/types";
import {
  C, IconTile, InfoRow, Item, Loading, Logo, NavItem, PageHead, Section, SelectItem, Sheet, StarPicker, Stars, StatusPill, Tiles, ToolButton, useToast,
} from "../components/ui";
import { Menu } from "../components/social";

const CATEGORY_ICONS: Record<SupportCategory, LucideIcon> = { account: UserRound, booking: CalendarDays, payment: CreditCard, studio: Mic, bug: Bug, other: MessageCircleQuestion };
const statusColor = (s: SupportStatus) => (s === "open" ? C.warning : s === "answered" ? C.positive : C.secondary);

export default function Support() {
  return (
    <Routes>
      <Route index element={<SupportCenter />} />
      <Route path="closed" element={<ClosedTickets />} />
      <Route path=":id" element={<TicketPage />} />
    </Routes>
  );
}

/** "Contact support": the user's requests to the EasySesh team, answered from the admin dashboard. */
function SupportCenter() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const bookingId = params.get("booking");
  const [composing, setComposing] = useState(!!bookingId);
  const { data: tickets, loading, setData } = useLoad(() => api.supportTickets(), []);
  const { data: booking } = useLoad(() => (bookingId ? api.booking(bookingId) : Promise.resolve(null)), [bookingId]);
  const active = (tickets ?? []).filter((x) => x.status !== "closed");
  const closed = (tickets ?? []).filter((x) => x.status === "closed");
  const unrated = closed.filter((x) => x.rating == null).length;

  return (
    <main className="page narrow">
      <PageHead title="Help & support" />
      <div className="stack-lg">
        <Section>
          <Item onClick={() => setComposing(true)}>
            <IconTile icon={MessagesSquare} size={44} />
            <div className="label"><div className="headline">{t("Contact support")}</div><div className="subhead secondary">{t("We usually reply within 24 hours.")}</div></div>
            <PlusCircle size={26} color="var(--accent)" />
          </Item>
        </Section>
        {loading ? <Loading /> : active.length > 0 ? (
          <Section header="Active">{active.map((x) => <Item key={x.id} to={`/support/${x.id}`}><TicketRow ticket={x} /></Item>)}</Section>
        ) : (
          <Section><Item><span className="subhead secondary">{t("Questions about a booking, a payment or your account? Send us a message and the EasySesh team will answer here.")}</span></Item></Section>
        )}
        {closed.length > 0 && (
          <Section>
            <Item to="/support/closed">
              <IconTile icon={Archive} size={30} colors={Tiles.muted} radius={8} />
              <div className="label"><div>{t("Closed")}</div>{unrated > 0 && <div className="caption accent">{format("%lld waiting for your rating", unrated)}</div>}</div>
              <span className="value">{closed.length}</span>
            </Item>
          </Section>
        )}
        <Section header="Policies">
          <NavItem to="/legal/refunds" title="Refund & cancellation policy" icon={Undo2} colors={Tiles.ocean} />
          <NavItem to="/legal" title="Terms & privacy" icon={FileText} colors={Tiles.muted} />
        </Section>
      </div>
      <NewTicketSheet open={composing} onClose={() => setComposing(false)} booking={booking ?? null}
        onCreated={(ticket) => { setData([ticket, ...(tickets ?? [])]); navigate(`/support/${ticket.id}`); }} />
    </main>
  );
}

function TicketRow({ ticket }: { ticket: SupportTicket }) {
  const Icon = CATEGORY_ICONS[ticket.category] ?? CircleHelp;
  return (
    <div className="row top grow" style={{ gap: 12 }}>
      <Icon size={20} color="var(--accent)" style={{ marginTop: 2, flexShrink: 0 }} />
      <div className="grow" style={{ display: "flex", flexDirection: "column", gap: 3, minWidth: 0 }}>
        <div className="row"><span className="grow subhead clamp-1" style={{ fontWeight: ticket.user_unread > 0 ? 700 : 600 }}>{ticket.subject}</span><span className="caption tertiary">{Dates.relative(ticket.last_message_at)}</span></div>
        <div className="subhead secondary clamp-2">{ticket.last_message_preview}</div>
        <div className="row" style={{ gap: 6 }}><StatusPill text={SUPPORT_STATUS_TITLE[ticket.status]} color={statusColor(ticket.status)} />{ticket.user_unread > 0 && <span style={{ width: 8, height: 8, borderRadius: 4, background: "var(--accent)" }} />}</div>
      </div>
    </div>
  );
}

function NewTicketSheet({ open, onClose, booking, onCreated }: { open: boolean; onClose: () => void; booking: Booking | null; onCreated: (t: SupportTicket) => void }) {
  const app = useApp();
  const toast = useToast();
  const [category, setCategory] = useState<SupportCategory>("other");
  const [subject, setSubject] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  useEffect(() => { if (booking && !subject) { setCategory("booking"); setSubject(`Booking ${booking.reference}`); } }, [booking]); // eslint-disable-line react-hooks/exhaustive-deps
  const canSend = subject.trim().length >= 3 && message.trim().length >= 10 && !sending;
  const categories = app.account?.role === "studio_owner" ? SUPPORT_CATEGORIES : SUPPORT_CATEGORIES.filter(([c]) => c !== "studio");
  async function send() {
    setSending(true);
    try { const ticket = await api.createSupportTicket(subject, category, message, booking?.id ?? null); setMessage(""); setSubject(""); onClose(); onCreated(ticket); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={open} onClose={onClose} title="Contact support" closeLabel="Cancel" actions={<ToolButton title={sending ? "Sending…" : "Send"} bold disabled={!canSend} onClick={send} />}>
      <div className="stack-lg">
        <Section header="What's it about?"><SelectItem title="Topic" value={category} options={categories} onChange={setCategory} icon={CATEGORY_ICONS[category]} /></Section>
        {booking && <Section header="Booking"><Item><InfoRow icon={CalendarDays} title={booking.reference} value={`${booking.studio_name} · ${Dates.abbreviatedWithTime(booking.starts_at)}`} translate={false} /></Item></Section>}
        <Section footer="Please don't share card numbers or passwords. The EasySesh team can see your account and bookings.">
          <Item><input placeholder={t("Subject")} value={subject} onChange={(e) => setSubject(e.target.value)} /></Item>
          <Item><textarea rows={7} placeholder={t("Describe what happened…")} value={message} onChange={(e) => setMessage(e.target.value)} /></Item>
        </Section>
        <button className="btn primary block" disabled={!canSend} onClick={send}>{t(sending ? "Sending…" : "Send")}</button>
      </div>
    </Sheet>
  );
}

function TicketPage() {
  const { id = "" } = useParams();
  const toast = useToast();
  const [ticket, setTicket] = useState<SupportTicket | null>(null);
  const [messages, setMessages] = useState<SupportMessage[]>([]);
  const [draft, setDraft] = useState("");
  const bottom = useRef<HTMLDivElement>(null);
  useEffect(() => {
    (async () => {
      try {
        const loaded = await api.supportTicket(id);
        setTicket(loaded);
        setMessages(await api.supportMessages(id));
        if (loaded.user_unread > 0) { await api.markSupportTicketRead(id); setTicket({ ...loaded, user_unread: 0 }); }
      } catch (e) { toast(userMessage(e)); }
    })();
  }, [id, toast]);
  useEffect(() => { bottom.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length]);
  if (!ticket) return <Loading />;
  const Icon = CATEGORY_ICONS[ticket.category] ?? CircleHelp;

  async function send() {
    const text = draft;
    if (!text.trim()) return;
    setDraft("");
    try {
      const m = await api.sendSupportMessage(id, text);
      setMessages((l) => [...l, m]);
      setTicket((x) => x && { ...x, status: "open", last_message_preview: m.body.slice(0, 140), last_message_at: m.created_at });
    } catch (e) { setDraft(text); toast(userMessage(e)); }
  }
  async function close() {
    try { setTicket(await api.closeSupportTicket(id)); } catch (e) { toast(userMessage(e)); }
  }

  return (
    <main className="page narrow">
      <PageHead title="Support" actions={ticket.status !== "closed" && <Menu entries={[{ title: "Mark as solved", icon: CheckCircle2, onClick: close }]} />} />
      <div className="stack" style={{ minHeight: "calc(100vh - 200px)" }}>
        <div className="stack center" style={{ alignItems: "center", gap: 6, paddingBottom: 8 }}>
          <Icon size={26} color="var(--accent)" />
          <div className="headline">{ticket.subject}</div>
          <StatusPill text={SUPPORT_STATUS_TITLE[ticket.status]} color={statusColor(ticket.status)} />
        </div>
        <div className="grow stack" style={{ gap: 10 }}>
          {messages.map((m) => (
            <div key={m.id} style={{ display: "flex", flexDirection: "column", alignItems: m.from_admin ? "flex-start" : "flex-end", gap: 3 }}>
              {m.from_admin && <div className="row caption2 semibold secondary" style={{ gap: 4 }}><Logo size={11} />{t("support")}</div>}
              <div className={`bubble ${m.from_admin ? "theirs" : "mine"}`}>{m.body}</div>
              <div className="caption2 secondary">{Dates.abbreviatedWithTime(m.created_at)}</div>
            </div>
          ))}
          {ticket.status === "closed" && (
            <>
              <RatingCard ticket={ticket} onChange={setTicket} />
              <div className="caption secondary center">{t("This request is closed. Send a message to reopen it.")}</div>
            </>
          )}
          <div ref={bottom} />
        </div>
        <form className="chat-input" style={{ position: "sticky", bottom: 0, background: "color-mix(in srgb, var(--bg) 90%, transparent)", backdropFilter: "blur(14px)" }} onSubmit={(e) => { e.preventDefault(); send(); }}>
          <textarea rows={1} placeholder={t("Message")} value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} />
          <button className="send-btn" type="submit" disabled={!draft.trim()} aria-label={t("Send")}><ArrowUp size={20} /></button>
        </form>
      </div>
    </main>
  );
}

/** Shown in a closed request: rate how support handled it. */
function RatingCard({ ticket, onChange }: { ticket: SupportTicket; onChange: (t: SupportTicket) => void }) {
  const toast = useToast();
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState("");
  const [editing, setEditing] = useState(false);
  const [sending, setSending] = useState(false);
  async function send() {
    setSending(true);
    try { onChange(await api.rateSupportTicket(ticket.id, rating, comment.trim())); setEditing(false); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  if (ticket.rating != null && !editing) {
    return (
      <div className="card row" style={{ marginTop: 8 }}>
        <div className="grow stack" style={{ gap: 6 }}>
          <div className="subhead bold">{t("Thanks for your feedback!")}</div>
          <Stars rating={ticket.rating} size={16} />
          {ticket.rating_comment && <div className="subhead secondary">“{ticket.rating_comment}”</div>}
        </div>
        <button className="link-btn" onClick={() => { setRating(ticket.rating!); setComment(ticket.rating_comment ?? ""); setEditing(true); }}>{t("Edit")}</button>
      </div>
    );
  }
  return (
    <div className="card stack" style={{ marginTop: 8 }}>
      <div className="headline">{t("How did we do?")}</div>
      <div className="subhead secondary">{t("Rate how the EasySesh team handled your request.")}</div>
      <StarPicker value={rating} onChange={setRating} />
      <label className="field area"><textarea rows={2} placeholder={t("Anything we could do better? (optional)")} value={comment} onChange={(e) => setComment(e.target.value)} /></label>
      <button className="btn primary block" disabled={rating === 0 || sending} onClick={send}>{t(sending ? "Sending…" : "Send rating")}</button>
    </div>
  );
}

/** The "Closed" folder: finished requests and their ratings. */
function ClosedTickets() {
  const { data: tickets } = useLoad(() => api.supportTickets(), []);
  if (!tickets) return <Loading />;
  return (
    <main className="page narrow">
      <PageHead title="Closed" />
      <Section>
        {tickets.filter((x) => x.status === "closed").map((x) => (
          <Item key={x.id} to={`/support/${x.id}`}>
            <div className="grow stack" style={{ gap: 6 }}>
              <TicketRow ticket={x} />
              <div style={{ paddingLeft: 32 }}>{x.rating != null ? <Stars rating={x.rating} size={12} /> : <span className="row caption semibold accent" style={{ gap: 4 }}><Star size={13} />{t("Rate this request")}</span>}</div>
            </div>
          </Item>
        ))}
      </Section>
    </main>
  );
}

