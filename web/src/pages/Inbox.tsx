import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import {
  BadgeCheck, Banknote, Bell, BellRing, CalendarClock, CalendarPlus, CheckCircle2, Hand, Info, MessageCircle, PencilLine, ShieldCheck, ShieldX, Star, Trash2, Undo2, XCircle, AlarmClock,
  type LucideIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import type { AppNotification, NotificationKind } from "../lib/types";
import { C, ConfirmDialog, Empty, GlowHead, IconTile, LargeHead, Sheet, Tiles, useToast } from "../components/ui";

const ICONS: Record<NotificationKind, LucideIcon> = {
  booking_confirmed: BadgeCheck, booking_changed: CalendarClock, booking_cancelled: XCircle, booking_declined: XCircle, session_reminder: AlarmClock,
  refund_issued: Undo2, review_reminder: Star, booking_requested: CalendarPlus, new_review: Star, payout_sent: Banknote, studio_approved: ShieldCheck,
  studio_rejected: ShieldX, studio_changes_requested: PencilLine, new_message: MessageCircle, system: Info,
};

function palette(kind: NotificationKind): string[] {
  if (["booking_confirmed", "studio_approved", "payout_sent"].includes(kind)) return Tiles.mint;
  if (["booking_cancelled", "booking_declined", "studio_rejected", "refund_issued"].includes(kind)) return [C.red, C.magenta];
  if (kind === "new_message") return Tiles.ocean;
  if (kind === "new_review" || kind === "review_reminder") return [C.warning, C.accent];
  return Tiles.signal;
}

export default function Inbox() {
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const [pendingLinks, setPendingLinks] = useState<string[]>([]);
  const [linkRequest, setLinkRequest] = useState<AppNotification | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [reading, setReading] = useState<AppNotification | null>(null);
  const notes = app.notifications;
  const fresh = notes.filter((n) => !n.is_read);
  const earlier = notes.filter((n) => n.is_read);
  const role = app.account!.role;

  useEffect(() => {
    app.refreshBadges();
    if (role === "artist") api.artistStudioLinks(app.account!.id).then((links) => setPendingLinks(links.filter((l) => l.status !== "accepted").map((l) => l.studio_id))).catch(() => undefined);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const isLinkRequest = (n: AppNotification) => !!n.studio_id && !n.booking_id && !n.conversation_id && pendingLinks.includes(n.studio_id);

  async function markRead(n: AppNotification) {
    if (n.is_read) return;
    app.setNotifications(notes.map((x) => (x.id === n.id ? { ...x, is_read: true } : x)));
    await api.markNotificationRead(n.id).catch(() => undefined);
  }
  async function remove(n: AppNotification) {
    app.setNotifications(notes.filter((x) => x.id !== n.id));
    await api.deleteNotification(n.id).catch(() => undefined);
  }
  async function respond(n: AppNotification, accept: boolean) {
    try { await api.respondStudioArtistLink(n.studio_id!, accept); setPendingLinks((l) => l.filter((x) => x !== n.studio_id)); markRead(n); } catch (e) { toast(userMessage(e)); }
  }
  /** Where the notification's button goes (same targets as a push notification tap in the apps). */
  function target(n: AppNotification): { to: string; title: string } | null {
    if (n.conversation_id) return { to: `/messages/${n.conversation_id}`, title: "Open chat" };
    if (n.booking_id) return { to: `/sessions/${n.booking_id}`, title: "View booking" };
    if (n.studio_id) return role === "studio_owner" ? { to: "/studio", title: "Open your studio" } : { to: `/studios/${n.studio_id}`, title: "View studio" };
    return null;
  }
  /** Messages open the chat; everything else opens so it can be read in full. */
  function open(n: AppNotification) {
    markRead(n);
    if (isLinkRequest(n)) { setLinkRequest(n); return; }
    if (n.kind === "new_message" && n.conversation_id) navigate(`/messages/${n.conversation_id}`);
    else setReading(n);
  }

  const row = (n: AppNotification) => (
    <div key={n.id} className="card row top pressable" style={{ padding: 14, position: "relative" }} onClick={() => open(n)}>
      <IconTile icon={ICONS[n.kind] ?? Info} size={40} colors={n.is_read ? Tiles.muted : palette(n.kind)} />
      <div className="grow" style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <div className="row" style={{ gap: 6 }}>
          <span className="grow subhead clamp-2" style={{ fontWeight: n.is_read ? 600 : 800 }}>{t(n.title)}</span>
          <span className="caption2 tertiary">{Dates.relative(n.created_at)}</span>
        </div>
        <div className="subhead secondary clamp-3">{n.body}</div>
        {isLinkRequest(n) && <div className="row caption semibold accent" style={{ gap: 4, marginTop: 4 }}><Hand size={13} />{t("Tap to connect or decline")}</div>}
      </div>
      <button className="msg-action" style={{ opacity: 0.7 }} onClick={(e) => { e.stopPropagation(); remove(n); }} aria-label={t("Delete")}><Trash2 size={16} /></button>
      {!n.is_read && <span style={{ position: "absolute", top: 8, right: 8, width: 9, height: 9, borderRadius: 5, background: "var(--primary)" }} />}
    </div>
  );

  return (
    <main className="page narrow">
      <LargeHead title="Inbox" eyebrow={fresh.length ? format("%lld new", fresh.length) : "Notifications"} actions={<>
        {fresh.length > 0 && <button className="icon-btn" onClick={async () => { app.setNotifications(notes.map((n) => ({ ...n, is_read: true }))); await api.markAllNotificationsRead().catch(() => undefined); }} aria-label={t("Mark all read")}><CheckCircle2 size={18} /></button>}
        {notes.length > 0 && <button className="icon-btn" onClick={() => setConfirmClear(true)} aria-label={t("Clear all")}><Trash2 size={18} /></button>}
      </>} />
      <div className="stack">
        {notes.length === 0 && <Empty icon={BellRing} title="You're all caught up" message="Bookings, messages and payouts show up here." />}
        {fresh.length > 0 && <><GlowHead title="New" count={fresh.length} />{fresh.map(row)}</>}
        {earlier.length > 0 && <><GlowHead title="Earlier" />{earlier.map(row)}</>}
      </div>
      {reading && (
        <Sheet open onClose={() => setReading(null)} title={t(reading.title)} translateTitle={false}>
          <div className="stack">
            <div className="card stack" style={{ gap: 10 }}>
              <div className="row" style={{ gap: 10 }}>
                <IconTile icon={ICONS[reading.kind] ?? Info} size={40} colors={palette(reading.kind)} />
                <span className="caption secondary">{Dates.abbreviatedWithTime(reading.created_at)}</span>
              </div>
              <div className="body" style={{ whiteSpace: "pre-wrap", lineHeight: 1.5 }}>{reading.body}</div>
            </div>
            {target(reading) && <button className="btn primary block" onClick={() => { const to = target(reading)!.to; setReading(null); navigate(to); }}>{t(target(reading)!.title)}</button>}
            {reading.kind === "system" && <Link to="/settings/history" className="btn secondary block" onClick={() => setReading(null)}>{t("Warnings & account history")}</Link>}
            <p className="footnote secondary" style={{ margin: "0 4px" }}>{t("Questions? Reply to the email or contact support.")}</p>
          </div>
        </Sheet>
      )}
      <ConfirmDialog open={confirmClear} onClose={() => setConfirmClear(false)} title="Delete all notifications?"
        actions={[{ title: "Delete all", destructive: true, action: async () => { app.setNotifications([]); await api.deleteAllNotifications().catch(() => undefined); } }]} />
      {linkRequest && (
        <ConfirmDialog open onClose={() => setLinkRequest(null)} title={t(linkRequest.title)} translateTitle={false} message={linkRequest.body}
          actions={[
            { title: "Connect", action: () => respond(linkRequest, true) },
            { title: "Decline", destructive: true, action: () => respond(linkRequest, false) },
            { title: "View studio", action: () => navigate(`/studios/${linkRequest.studio_id}`) },
          ]} />
      )}
    </main>
  );
}

export const InboxIcon = Bell;
