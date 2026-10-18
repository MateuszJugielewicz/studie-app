import { useEffect, useRef, useState } from "react";
import { Link, Route, Routes, useNavigate, useParams } from "react-router-dom";
import { ArrowUp, CalendarDays, Check, ChevronLeft, ChevronRight, Copy, Flag, Hand, HandMetal, Info, Inbox as InboxIcon, MessagesSquare, Search, SquarePen, Star, Trash2 } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { BOOKING_STATUS_TITLE, type ArtistSearchResult, type BlockState, type Booking, type ChatMessage, type Conversation, type UserRole } from "../lib/types";
import {
  AdminBadge, Avatar, bookingStatusColor, ConfirmDialog, Empty, IconTile, Item, LargeHead, Loading, Photo, Section, Sheet, StatusPill, Tiles, ToolButton, VerifiedBadge, useToast,
} from "../components/ui";
import { Menu, ReportSheet } from "../components/social";

type Filter = "all" | "unread" | "requests";
const status = (c: Conversation) => c.request_status ?? "accepted";
const unreadFor = (c: Conversation, role: UserRole) => (role === "artist" ? c.artist_unread : c.studio_unread);
const badge = (c: Conversation, role: UserRole) => (role === "artist" && status(c) !== "accepted" ? 0 : unreadFor(c, role));
const titleFor = (c: Conversation, role: UserRole) => (role === "artist" ? c.studio_name : c.artist_name);

export default function Chat() {
  return (
    <Routes>
      <Route index element={<Layout />} />
      <Route path=":id" element={<Layout />} />
    </Routes>
  );
}

/** List and thread side by side on wide screens; one at a time on phones (like the app). */
function Layout() {
  const { id } = useParams();
  return (
    <main className="page wide">
      <div className="chat-layout" data-open={id ? "thread" : "list"}>
        <div className="chat-list"><ConversationList activeId={id} /></div>
        <div className="chat-thread">{id ? <ChatThread key={id} id={id} /> : <div className="hide-mobile"><Empty icon={MessagesSquare} title="Messages" message="Message a studio from its profile or from one of your bookings." /></div>}</div>
      </div>
    </main>
  );
}

function ConversationList({ activeId }: { activeId?: string }) {
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const role = app.account!.role;
  const [conversations, setConversations] = useState<Conversation[] | null>(null);
  const [filter, setFilter] = useState<Filter>("all");
  const [composing, setComposing] = useState(false);

  const load = () => api.conversations().then(setConversations).catch((e) => toast(userMessage(e)));
  useEffect(() => { load(); }, [activeId]); // eslint-disable-line react-hooks/exhaustive-deps

  const list = conversations ?? [];
  const requests = list.filter((c) => status(c) === "pending");
  const visible = filter === "all" ? (role === "artist" ? list.filter((c) => status(c) === "accepted") : list) : filter === "unread" ? list.filter((c) => badge(c, role) > 0) : requests;
  const unread = list.reduce((n, c) => n + badge(c, role), 0);
  async function respond(c: Conversation, accept: boolean) {
    try { const u = await api.respondToMessageRequest(c.id, accept); setConversations(list.map((x) => (x.id === u.id ? u : x))); } catch (e) { toast(userMessage(e)); }
  }
  const filterTitle = (f: Filter) => (f === "all" ? t("All") : f === "unread" ? t("Unread") : role === "artist" ? t("Requests") : t("Sent requests"));

  return (
    <div className="stack">
      <LargeHead title="Messages" eyebrow={unread > 0 ? format("%lld unread", unread) : "Inbox"} actions={
        role === "studio_owner" && app.ownedStudio?.status === "approved"
          ? <button className="icon-btn" onClick={() => setComposing(true)} aria-label={t("New message")}><SquarePen size={18} /></button> : undefined
      } />
      <div className="row" style={{ gap: 8, overflowX: "auto" }}>
        {(["all", "unread", "requests"] as Filter[]).map((f) => (
          <span key={f} style={{ position: "relative" }}>
            <button className={`chip ${filter === f ? "on" : ""}`} onClick={() => setFilter(f)}>{filterTitle(f)}</button>
            {f === "requests" && requests.length > 0 && <span className="badge-count" style={{ position: "absolute", top: -6, right: -4, background: "var(--accent)" }}>{requests.length}</span>}
          </span>
        ))}
      </div>
      {role === "artist" && filter === "all" && requests.length > 0 && (
        <button className="card tight row pressable" style={{ textAlign: "left" }} onClick={() => setFilter("requests")}>
          <IconTile icon={InboxIcon} colors={Tiles.violet} />
          <span className="grow"><div className="subhead bold">{t("Message requests")}</div><div className="caption secondary">{requests.length === 1 ? t("1 studio wants to talk to you") : format("%lld studios want to talk to you", requests.length)}</div></span>
          <ChevronRight size={16} className="tertiary" />
        </button>
      )}
      {conversations == null ? <Loading /> : visible.length === 0 ? (
        <Empty icon={filter === "requests" ? InboxIcon : MessagesSquare}
          title={filter === "all" ? "No messages yet" : filter === "unread" ? "You're all caught up" : role === "artist" ? "No message requests" : "No pending requests"}
          message={filter === "requests"
            ? (role === "artist" ? "When a studio you haven't booked writes to you, it shows up here first." : "Artists you message who haven't booked you yet see it as a request until they accept.")
            : (role === "artist" ? "Message a studio from its profile or from one of your bookings." : "Artists can message you about your studio and bookings. Tap ✎ to write to an artist.")} />
      ) : visible.map((c) => (
        <div key={c.id} className="row" style={{ gap: 6 }}>
          <button className="grow" style={{ textAlign: "left" }} onClick={() => navigate(`/messages/${c.id}`)}>
            <ConversationRow conversation={c} role={role} active={c.id === activeId} />
          </button>
          {role === "artist" && status(c) === "pending" && (
            <Menu entries={[{ title: "Accept", icon: Check, onClick: () => respond(c, true) }, { title: "Delete request", icon: Trash2, destructive: true, onClick: () => respond(c, false) }]} />
          )}
        </div>
      ))}
      <NewMessageSheet open={composing} onClose={() => setComposing(false)} onSent={(c) => { setConversations([c, ...list.filter((x) => x.id !== c.id)]); navigate(`/messages/${c.id}`); }} />
    </div>
  );
}

function ConversationRow({ conversation: c, role, active }: { conversation: Conversation; role: UserRole; active?: boolean }) {
  const unread = unreadFor(c, role);
  return (
    <div className="card tight row" style={{ gap: 12, border: active ? "1.5px solid var(--magenta)" : undefined }}>
      <span style={{ padding: 2.5, borderRadius: "50%", background: unread > 0 ? "var(--neon)" : "var(--fill)", display: "inline-flex", flexShrink: 0 }}>
        {role === "artist" ? <Photo url={c.studio_photo_url} style={{ width: 52, height: 52, borderRadius: "50%" }} /> : <Avatar url={c.artist_avatar_url} name={c.artist_name} size={52} />}
      </span>
      <div className="grow" style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        <div className="row" style={{ gap: 6 }}>
          <span className="grow headline clamp-1" style={{ fontWeight: unread > 0 ? 800 : 600 }}>{titleFor(c, role)}</span>
          <span className="caption" style={{ color: unread > 0 ? "var(--accent)" : "var(--text-2)" }}>{Dates.relative(c.last_message_at)}</span>
        </div>
        <div className="row" style={{ gap: 6 }}>
          {status(c) === "pending" ? <Tag text={role === "artist" ? "Request" : "Request sent"} icon={InboxIcon} />
            : status(c) === "declined" && role === "studio_owner" ? <Tag text="Declined" icon={Hand} />
            : c.booking_id ? <CalendarDays size={13} color="var(--accent)" /> : null}
          <span className="grow subhead clamp-1" style={{ color: unread > 0 ? "var(--text)" : "var(--text-2)" }}>{c.last_message_preview || t("New conversation")}</span>
          {unread > 0 && <span className="caption bold" style={{ background: "var(--neon)", color: "#fff", borderRadius: 999, padding: "2px 7px" }}>{unread}</span>}
        </div>
      </div>
    </div>
  );
}

function Tag({ text, icon: Icon }: { text: string; icon: typeof Hand }) {
  return <span className="pill" style={{ background: "color-mix(in srgb, var(--violet) 15%, transparent)", color: "var(--violet)" }}><Icon size={11} />{t(text)}</span>;
}

function ChatThread({ id }: { id: string }) {
  const app = useApp();
  const toast = useToast();
  const role = app.account!.role;
  const isStudio = role === "studio_owner";
  const [conversation, setConversation] = useState<Conversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [booking, setBooking] = useState<Booking | null>(null);
  const [blockState, setBlockState] = useState<BlockState>("none");
  const [partner, setPartner] = useState<{ avatar?: string | null; rating?: [number, number] } | null>(null);
  const [reporting, setReporting] = useState<{ target: "message" | "user" | "studio"; id: string } | null>(null);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let stop = () => {};
    (async () => {
      try {
        const c = await api.conversationById(id);
        setConversation(c);
        setMessages(await api.messages(id));
        api.markConversationRead(id).then(() => app.refreshBadges()).catch(() => undefined);
        if (c.booking_id) api.booking(c.booking_id).then(setBooking).catch(() => undefined);
        api.conversationBlockState(id).then(setBlockState).catch(() => undefined);
        if (isStudio) api.artistProfile(c.artist_id).then((p) => p && setPartner({ avatar: p.avatar_url, rating: [p.rating_average ?? 0, p.review_count ?? 0] })).catch(() => undefined);
        else api.studio(c.studio_id).then((s) => setPartner({ avatar: s.photo_urls[0], rating: [s.rating_average, s.review_count] })).catch(() => undefined);
        stop = api.subscribeMessages(id, (m) => {
          setMessages((list) => (list.some((x) => x.id === m.id) ? list : [...list, m]));
          api.markConversationRead(id).catch(() => undefined);
        });
      } catch (e) { toast(userMessage(e)); }
    })();
    return () => stop();
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" }); }, [messages.length]);

  if (!conversation) return <Loading />;
  const name = titleFor(conversation, role);
  const photo = partner?.avatar ?? (isStudio ? conversation.artist_avatar_url : conversation.studio_photo_url);

  async function send() {
    const text = draft;
    if (!text.trim()) return;
    setDraft("");
    try { const m = await api.sendMessage(id, text); setMessages((list) => (list.some((x) => x.id === m.id) ? list : [...list, m])); } catch (e) { setDraft(text); toast(userMessage(e)); }
  }
  async function setBlocked(blocked: boolean) {
    try { setBlockState(await api.setConversationBlock(id, blocked)); } catch (e) { toast(userMessage(e)); }
  }
  async function respond(accept: boolean) {
    try { setConversation(await api.respondToMessageRequest(id, accept)); } catch (e) { toast(userMessage(e)); }
  }

  return (
    <div className="stack" style={{ minHeight: "calc(100vh - 160px)" }}>
      <div className="page-head">
        <div className="side"><Link to="/messages" className="icon-btn chat-back" aria-label={t("Back")}><ChevronLeft size={22} /></Link></div>
        <Link to={isStudio ? `/artists/${conversation.artist_id}` : `/studios/${conversation.studio_id}`} className="row grow" style={{ justifyContent: "center", gap: 8, minWidth: 0 }}>
          {isStudio ? <Avatar url={photo} name={name} size={32} ring /> : <span className="ring"><Photo url={photo} style={{ width: 32, height: 32, borderRadius: "50%" }} /></span>}
          <span style={{ minWidth: 0 }}>
            <div className="subhead bold clamp-1">{name}</div>
            {partner?.rating && partner.rating[1] > 0
              ? <div className="row caption2" style={{ gap: 3 }}><Star size={11} fill="var(--accent)" color="var(--accent)" /><b>{partner.rating[0].toFixed(1)}</b><span className="secondary">({partner.rating[1]})</span></div>
              : <div className="caption2 secondary">{t(partner == null ? (isStudio ? "View artist profile" : "View studio") : "No ratings yet")}</div>}
          </span>
          <ChevronRight size={12} className="tertiary" />
        </Link>
        <div className="side end">
          <Menu entries={[
            { title: isStudio ? "Report artist" : "Report studio", icon: Flag, onClick: () => setReporting({ target: isStudio ? "user" : "studio", id: isStudio ? conversation.artist_id : conversation.studio_id }) },
            blockState === "by_me" ? { title: "Unblock", icon: HandMetal, onClick: () => setBlocked(false) } : { title: isStudio ? "Block artist" : "Block studio", icon: Hand, destructive: true, onClick: () => setConfirmBlock(true) },
          ]} />
        </div>
      </div>
      {booking && (
        <Link to={`/sessions/${booking.id}`} className="card tight row" style={{ borderRadius: 18 }}>
          <CalendarDays size={15} /><span className="grow footnote clamp-1">{booking.session_type_name} · {Dates.abbreviatedWithTime(booking.starts_at)}</span>
          <StatusPill text={BOOKING_STATUS_TITLE[booking.status]} color={bookingStatusColor(booking.status)} />
        </Link>
      )}
      <div className="caption2 secondary center">{t("Keep payments and bookings inside EasySesh – you're protected by our refund policy.")}</div>
      <div className="grow stack" style={{ gap: 8 }}>
        {messages.map((m, i) => {
          const mine = m.sender_id === app.account?.id;
          if (m.kind !== "text") return <div key={m.id} className="row caption secondary" style={{ justifyContent: "center", gap: 4, background: "var(--card)", borderRadius: 10, padding: 8 }}><Info size={13} />{m.body}</div>;
          const lastInRun = i === messages.length - 1 || messages[i + 1].sender_id !== m.sender_id;
          return (
            <div key={m.id} className="row" style={{ alignItems: "flex-end", gap: 8, justifyContent: mine ? "flex-end" : "flex-start" }}>
              {!mine && <span style={{ opacity: lastInRun ? 1 : 0 }}><Avatar url={photo} name={name} size={26} /></span>}
              <div style={{ display: "flex", flexDirection: "column", alignItems: mine ? "flex-end" : "flex-start", gap: 2, maxWidth: "75%" }} className="bubble-wrap">
                <div className={`bubble ${mine ? "mine" : "theirs"}`} style={{ maxWidth: "100%" }}>{m.body}</div>
                <div className="row caption2 secondary" style={{ gap: 6 }}>
                  {Dates.time(m.created_at)}
                  <button className="msg-action" onClick={() => navigator.clipboard?.writeText(m.body)} aria-label={t("Copy")}><Copy size={11} /></button>
                  {!mine && m.sender_id && <button className="msg-action" onClick={() => setReporting({ target: "message", id: m.id })} aria-label={t("Report message")}><Flag size={11} /></button>}
                </div>
              </div>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>
      <div style={{ position: "sticky", bottom: 0, background: "color-mix(in srgb, var(--bg) 90%, transparent)", backdropFilter: "blur(14px)", paddingBottom: 8 }}>
        {blockState !== "none" ? (
          <div className="stack center" style={{ padding: 14, alignItems: "center", gap: 8 }}>
            <div className="row footnote semibold secondary" style={{ gap: 6 }}><Hand size={14} />{t(blockState === "by_me" ? "You blocked this account." : "You can't reply to this conversation.")}</div>
            {blockState === "by_me" && <button className="link-btn footnote" onClick={() => setBlocked(false)}>{t("Unblock")}</button>}
          </div>
        ) : role === "artist" && status(conversation) === "pending" ? (
          <div className="stack center" style={{ padding: 14, alignItems: "center", gap: 10 }}>
            <div className="subhead semibold">{format("%@ wants to send you a message", conversation.studio_name)}</div>
            <div className="caption secondary">{t("Accept to reply. They won't know you've seen it until you do.")}</div>
            <div className="row" style={{ gap: 10, width: "100%", maxWidth: 400 }}>
              <button className="btn danger grow" onClick={() => respond(false)}>{t("Delete")}</button>
              <button className="btn primary grow" onClick={() => respond(true)}>{t("Accept")}</button>
            </div>
          </div>
        ) : isStudio && status(conversation) === "declined" ? (
          <div className="row footnote secondary" style={{ justifyContent: "center", padding: 14, gap: 6 }}><Hand size={14} />{t("This artist isn't accepting messages from your studio.")}</div>
        ) : (
          <form className="chat-input" onSubmit={(e) => { e.preventDefault(); send(); }}>
            <textarea rows={1} placeholder={t("Message")} value={draft} onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} />
            <button type="submit" className="send-btn" disabled={!draft.trim()} aria-label={t("Send")}><ArrowUp size={20} /></button>
          </form>
        )}
      </div>
      <ConfirmDialog open={confirmBlock} onClose={() => setConfirmBlock(false)} translateTitle={false} title={format("Block %@?", name)}
        message={t("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts.")}
        actions={[{ title: "Block", destructive: true, action: () => setBlocked(true) }]} />
      {reporting && <ReportSheet open onClose={() => setReporting(null)} target={reporting.target} targetId={reporting.id} />}
    </div>
  );
}

/** Studio → artist: pick an artist (search, or someone who booked you) and write the first message. */
function NewMessageSheet({ open, onClose, onSent }: { open: boolean; onClose: () => void; onSent: (c: Conversation) => void }) {
  const toast = useToast();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<ArtistSearchResult[]>([]);
  const [chosen, setChosen] = useState<ArtistSearchResult | null>(null);
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  useEffect(() => {
    if (!open) return;
    const timer = window.setTimeout(() => api.searchArtists(query).then(setResults).catch((e) => toast(userMessage(e))), 300);
    return () => window.clearTimeout(timer);
  }, [query, open]); // eslint-disable-line react-hooks/exhaustive-deps
  async function send() {
    if (!chosen) return;
    setSending(true);
    try { const c = await api.startConversation(chosen.id, message); onClose(); setChosen(null); setMessage(""); onSent(c); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={open} onClose={() => (chosen ? setChosen(null) : onClose())} title={chosen?.artist_name ?? t("New message")} translateTitle={false} closeLabel={chosen ? "Back" : "Cancel"}
      actions={chosen && <ToolButton title={sending ? "Sending…" : "Send"} bold disabled={sending || !message.trim()} onClick={send} />}>
      {!chosen ? (
        <div className="stack-lg">
          <label className="field"><Search size={18} /><input placeholder={t("Search artists")} value={query} onChange={(e) => setQuery(e.target.value)} /></label>
          <Section header={query.length < 2 ? "Your artists" : "Artists"}>
            {results.length === 0 && <Item><span className="subhead secondary">{t(query.length < 2 ? "Artists who booked you appear here. Search to find others by name or city." : "No artists found.")}</span></Item>}
            {results.map((a) => (
              <Item key={a.id} onClick={() => setChosen(a)}>
                <Avatar url={a.avatar_url} name={a.artist_name} size={44} />
                <div className="label">
                  <div className="row headline" style={{ gap: 4 }}>{a.artist_name}{a.is_verified && <VerifiedBadge />}{a.has_admin_badge && <AdminBadge compact />}</div>
                  <div className="caption secondary">{[a.city, a.genres.slice(0, 2).join(", ")].filter(Boolean).join(" · ")}</div>
                </div>
                {a.has_booked && <span className="caption2 bold positive">{t("Booked you")}</span>}
              </Item>
            ))}
          </Section>
        </div>
      ) : (
        <div className="stack-lg">
          <Section><Item><Avatar url={chosen.avatar_url} name={chosen.artist_name} size={52} /><div className="label"><div className="headline">{chosen.artist_name}</div><div className="caption secondary">{t(chosen.has_booked ? "Goes straight to their inbox." : "They'll get it as a message request and can accept or delete it.")}</div></div></Item></Section>
          <Section footer="Be personal and relevant. Studios that spam artists can be suspended.">
            <Item><textarea rows={6} placeholder={t("Write a message…")} value={message} onChange={(e) => setMessage(e.target.value)} /></Item>
          </Section>
          <button className="btn primary block" disabled={sending || !message.trim()} onClick={send}>{t(sending ? "Sending…" : "Send")}</button>
        </div>
      )}
    </Sheet>
  );
}
