import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, Navigate, Route, Routes, useNavigate } from "react-router-dom";
import {
  ArrowDownCircle, Banknote, BarChart3, CalendarClock, CalendarDays, ChevronRight, CircleCheck, CircleDot, CircleUserRound, Clock, Eye, FileText,
  Hourglass, Inbox, Landmark, Link2, Megaphone, MessageSquareText, Moon, OctagonAlert, Pencil, Send, SlidersHorizontal, Sparkles, Star, Tag, Zap, Ban,
  CircleHelp, Check, Sigma, type LucideIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import {
  Dates, earningsSummary, greeting, Money, openingWindow, sameDay, startOfDay, Studios, studioZone, isActiveStatus, addDays,
} from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import {
  FEE_KIND_TITLE, PAYOUT_STATUS_TITLE, STUDIO_STATUS_TITLE, type BlockedSlot, type Booking, type FeeInvoice, type FeeLedgerEntry, type Payout, type Review, type Studio,
} from "../lib/types";
import {
  AdminBadge, C, Empty, GlowHead, IconTile, InfoRow, Item, LargeHead, Loading, MonthCalendar, NavItem, PageHead, Photo, PromotedTag, PulseDot,
  Section, Sheet, StatCard, StatusPill, studioStatusColor, TileLink, Tiles, Toggle, ToggleItem, ToolButton, VerifiedBadge, useToast,
} from "../components/ui";
import { BookingRow } from "./Bookings";
import { SignOutButton } from "./Profile";
import { PayoutPage, PromotionPage, ArtistLinkPage } from "./StudioExtras";

export default function StudioOwner() {
  const app = useApp();
  const studio = app.ownedStudio;
  const live = studio && ["approved", "suspended"].includes(studio.status);
  return (
    <Routes>
      <Route index element={!studio ? <Navigate to="/studio/edit" replace /> : live ? <Dashboard /> : <ApplicationStatus studio={studio} />} />
      <Route path="calendar" element={live ? <StudioCalendar /> : <Navigate to="/studio" replace />} />
      <Route path="listing" element={studio ? <StudioSettings /> : <Navigate to="/studio/edit" replace />} />
      <Route path="earnings" element={studio ? <Earnings /> : <Navigate to="/studio" replace />} />
      <Route path="bookings/past" element={studio ? <PastBookings /> : <Navigate to="/studio" replace />} />
      <Route path="payouts" element={studio ? <PayoutPage /> : <Navigate to="/studio" replace />} />
      <Route path="promotion" element={studio ? <PromotionPage /> : <Navigate to="/studio" replace />} />
      <Route path="artist-link" element={studio ? <ArtistLinkPage /> : <Navigate to="/studio" replace />} />
    </Routes>
  );
}

// MARK: Application

function ApplicationStatus({ studio }: { studio: Studio }) {
  const app = useApp();
  const toast = useToast();
  const [submitting, setSubmitting] = useState(false);
  useEffect(() => { api.ownedStudio().then((s) => s && app.setOwnedStudio(s)).catch(() => undefined); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const text: Record<string, string> = {
    draft: "Finish your listing and submit it. Our team checks every studio before it becomes visible.",
    pending_review: "Thanks! We're reviewing your studio and will notify you, usually within 1–2 business days.",
    changes_requested: "We need a few changes before we can approve your studio. Update your listing and resubmit.",
    rejected: "Unfortunately your studio wasn't approved. You can update your listing and apply again.",
  };
  async function submit() {
    setSubmitting(true);
    try { app.setOwnedStudio(await api.submitStudioForReview(studio.id)); } catch (e) { toast(userMessage(e)); }
    setSubmitting(false);
  }
  const color = studioStatusColor(studio.status);
  return (
    <main className="page narrow">
      <LargeHead title="Application" eyebrow={studio.name || "Your studio"} translate />
      <div className="stack">
        <div className="card big" style={{ position: "relative" }}>
          <span className="side-bar" style={{ top: 18, bottom: 18, width: 4 }} />
          <div className="row" style={{ gap: 10 }}><PulseDot color={color} active={studio.status === "pending_review"} /><span className="caption heavy" style={{ color, letterSpacing: "0.08em" }}>{t(STUDIO_STATUS_TITLE[studio.status]).toUpperCase()}</span></div>
          {text[studio.status] && <div style={{ marginTop: 14 }}>{t(text[studio.status])}</div>}
        </div>
        {studio.admin_note && (
          <div className="card row top">
            <IconTile icon={MessageSquareText} colors={Tiles.warm} />
            <div><div className="subhead bold">{t("Message from the EasySesh team")}</div><div className="subhead secondary pre">{studio.admin_note}</div></div>
          </div>
        )}
        <div className="card big" style={{ padding: 16 }}>
          <Step title="Create your listing" done />
          <Step title="Submit for review" done={studio.status !== "draft"} />
          <Step title="EasySesh reviews your studio" done={studio.status === "approved"} active={studio.status === "pending_review"} />
          <Step title="Go live – artists can find, book and pay" done={studio.status === "approved"} last />
        </div>
        {studio.status !== "pending_review" && <button className="btn primary block" disabled={submitting} onClick={submit}><Send size={18} />{t(submitting ? "Submitting…" : "Submit for review")}</button>}
        <Link to="/studio/edit" className="btn secondary block"><Pencil size={18} />{t("Edit listing")}</Link>
        <SignOutButton />
      </div>
    </main>
  );
}

function Step({ title, done, active, last }: { title: string; done?: boolean; active?: boolean; last?: boolean }) {
  const Icon = done ? Check : active ? Hourglass : CircleDot;
  return (
    <div className="row top" style={{ gap: 14 }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <span style={{ width: 30, height: 30, borderRadius: 15, display: "flex", alignItems: "center", justifyContent: "center", background: done ? "var(--neon)" : "var(--fill)", color: done ? "#fff" : active ? "var(--warning)" : "var(--text-2)", boxShadow: done ? "0 0 10px color-mix(in srgb, var(--magenta) 40%, transparent)" : undefined }}><Icon size={14} strokeWidth={3} /></span>
        {!last && <span style={{ width: 2, height: 26, background: done ? "var(--neon)" : "var(--fill)" }} />}
      </div>
      <span className="subhead" style={{ paddingTop: 5, fontWeight: done || active ? 700 : 400, color: done || active ? undefined : "var(--text-2)" }}>{t(title)}</span>
    </div>
  );
}

// MARK: Dashboard

function useStudioData(studio: Studio | null) {
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [fees, setFees] = useState<FeeLedgerEntry[]>([]);
  const [loaded, setLoaded] = useState(false);
  const load = useCallback(async () => {
    if (!studio) return;
    await Promise.all([
      api.studioBookings(studio.id).then(setBookings).catch(() => undefined),
      api.payouts(studio.id).then(setPayouts).catch(() => undefined),
      api.reviews(studio.id).then(setReviews).catch(() => undefined),
      api.feeLedger(studio.id).then(setFees).catch(() => undefined),
    ]);
    setLoaded(true);
  }, [studio?.id]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, [load]);
  return { bookings, payouts, reviews, fees, loaded, load };
}

function Dashboard() {
  const app = useApp();
  const navigate = useNavigate();
  const studio = app.ownedStudio!;
  const { bookings, payouts, reviews, fees, loaded } = useStudioData(studio);
  useEffect(() => { api.ownedStudio().then((s) => s && app.setOwnedStudio(s)).catch(() => undefined); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const summary = useMemo(() => earningsSummary(bookings, payouts), [bookings, payouts]);
  const requests = bookings.filter((b) => b.status === "pending_approval").sort((a, b) => +new Date(a.starts_at) - +new Date(b.starts_at));
  const upcoming = bookings.filter((b) => b.status === "confirmed" && new Date(b.ends_at) > new Date()).sort((a, b) => +new Date(a.starts_at) - +new Date(b.starts_at));
  const feesOwed = fees.reduce((n, f) => n + f.amount, 0);
  const card = (b: Booking, accent?: boolean) => (
    <button key={b.id} className="card tight pressable" style={{ textAlign: "left", width: "100%", position: "relative" }} onClick={() => navigate(`/sessions/${b.id}`)}>
      {accent && <span className="side-bar" />}<BookingRow booking={b} perspective="studio_owner" />
    </button>
  );
  return (
    <main className="page">
      <LargeHead title={studio.name} translate={false} eyebrow={greeting()} actions={<Link to={`/studios/${studio.id}`} className="icon-btn" aria-label={t("Preview public profile")}><Eye size={18} /></Link>} />
      <div className="two-col">
        <div className="stack">
          {studio.status === "suspended" && (
            <div className="card row"><IconTile icon={OctagonAlert} colors={Tiles.danger} /><span className="subhead">{t("Your studio is suspended and hidden from artists. Contact support.")}</span></div>
          )}
          <LiveToggle studio={studio} />
          <div className="neon-card stack" style={{ gap: 14 }}>
            <div className="row spread"><span className="subhead semibold" style={{ opacity: 0.85 }}>{t("Earned this month")}</span><BarChart3 size={16} style={{ opacity: 0.8 }} /></div>
            <div style={{ fontSize: 40, fontWeight: 800, lineHeight: 1 }}>{Money.format(summary.netThisMonth, studio.currency)}</div>
            <TrendLine values={summary.monthly.map((m) => m.amount)} />
            <div className="row caption semibold" style={{ gap: 4, position: "relative", zIndex: 1 }}>
              <ArrowDownCircle size={13} /><span className="grow">{format("Next payout %@", Money.format(summary.pendingPayout, studio.currency))}</span>
              <span style={{ opacity: 0.75 }}>{format("%lld%% platform fee", Studios.feePercent(studio))}</span>
            </div>
          </div>
          <div className="grid-3">
            <StatCard title="Upcoming" value={String(summary.upcomingSessions)} icon={CalendarDays} colors={Tiles.ocean} />
            <StatCard title="Requests" value={String(requests.length)} icon={Inbox} colors={Tiles.signal} />
            <StatCard title="Rating" value={studio.review_count === 0 ? "–" : studio.rating_average.toFixed(1)} icon={Star} colors={Tiles.violet} />
          </div>
          {feesOwed > 0 && (
            <div className="card row"><IconTile icon={Banknote} colors={Tiles.violet} /><span className="footnote">{format("You owe %@ in platform fees for cash bookings. It's deducted from your next payout.", Money.format(feesOwed, studio.currency))}</span></div>
          )}
          {requests.length > 0 && <><GlowHead title="Requests" count={requests.length} />{requests.map((b) => card(b, true))}</>}
          <GlowHead title="Upcoming" />
          {!loaded ? <Loading /> : upcoming.length === 0 ? <Empty icon={CalendarClock} title="No upcoming sessions" message="New bookings show up here the moment artists book." /> : upcoming.slice(0, 5).map((b) => card(b))}
        </div>
        <aside className="stack sticky">
          <GlowHead title="Manage" />
          <div className="card zero">
            <ManageLink to="/studio/earnings" title="Earnings & payouts" icon={BarChart3} colors={Tiles.mint} />
            <ManageLink to="/studio/bookings/past" title="Past bookings" icon={Clock} colors={Tiles.ocean} />
            <ManageLink to="/studio/edit/pricing" title="Prices & services" icon={Tag} colors={Tiles.signal} />
            <ManageLink to="/studio/edit/hours" title="Opening hours" icon={Clock} colors={Tiles.violet} />
            <ManageLink to={`/studios/${studio.id}/reviews`} title="Reviews" icon={Star} colors={Tiles.warm} badge={reviews.length} last />
          </div>
        </aside>
      </div>
    </main>
  );
}

function ManageLink({ to, title, icon, colors, badge, last }: { to: string; title: string; icon: LucideIcon; colors: string[]; badge?: number; last?: boolean }) {
  return (
    <Link to={to} className="row pressable" style={{ padding: "11px 14px", gap: 14, borderBottom: last ? undefined : "0.5px solid var(--stroke)" }}>
      <IconTile icon={icon} size={32} colors={colors} /><span className="grow" style={{ fontWeight: 500 }}>{t(title)}</span>
      {!!badge && <span className="subhead secondary">{badge}</span>}<ChevronRight size={14} className="tertiary" />
    </Link>
  );
}

function LiveToggle({ studio }: { studio: Studio }) {
  const app = useApp();
  const toast = useToast();
  async function set(active: boolean) {
    try { app.setOwnedStudio(await api.setStudioActive(studio.id, active)); } catch (e) { toast(userMessage(e)); }
  }
  return (
    <div className="card row">
      <PulseDot color={C.positive} active={studio.is_active} />
      <div className="grow"><div className="headline">{t(studio.is_active ? "Live on EasySesh" : "Paused")}</div><div className="caption secondary">{t(studio.is_active ? "Artists can find and book you." : "Hidden from search. Existing bookings are kept.")}</div></div>
      <Toggle checked={studio.is_active} onChange={set} disabled={studio.status !== "approved"} />
    </div>
  );
}

/** Smooth white six-month line (iOS Charts area + line). */
function TrendLine({ values }: { values: number[] }) {
  const w = 300, h = 64;
  const max = Math.max(...values, 1);
  const pts = values.map((v, i) => [values.length > 1 ? (i / (values.length - 1)) * w : 0, h - 3 - (v / max) * (h - 6)]);
  let line = `M${pts[0][0]},${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) { const mx = (pts[i - 1][0] + pts[i][0]) / 2; line += ` C${mx},${pts[i - 1][1]} ${mx},${pts[i][1]} ${pts[i][0]},${pts[i][1]}`; }
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ width: "100%", height: h, position: "relative", zIndex: 1 }} aria-hidden>
      <defs><linearGradient id="trend" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="#fff" stopOpacity="0.45" /><stop offset="1" stopColor="#fff" stopOpacity="0" /></linearGradient></defs>
      <path d={`${line} L${w},${h} L0,${h} Z`} fill="url(#trend)" />
      <path d={line} fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function PastBookings() {
  const app = useApp();
  const navigate = useNavigate();
  const { bookings, loaded } = useStudioData(app.ownedStudio);
  const past = bookings.filter((b) => !(new Date(b.ends_at) > new Date() && isActiveStatus(b.status)) && b.status !== "pending_approval");
  return (
    <main className="page narrow">
      <PageHead title="Past bookings" />
      {!loaded ? <Loading /> : past.length === 0 ? <Empty icon={CalendarDays} title="Nothing here yet" /> : (
        <div className="stack">{past.map((b) => <button key={b.id} className="card tight pressable" style={{ textAlign: "left" }} onClick={() => navigate(`/sessions/${b.id}`)}><BookingRow booking={b} perspective="studio_owner" /></button>)}</div>
      )}
    </main>
  );
}

// MARK: Calendar

function StudioCalendar() {
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const studio = app.ownedStudio!;
  const [day, setDay] = useState(startOfDay(new Date()));
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [blocked, setBlocked] = useState<BlockedSlot[]>([]);
  const [showBlock, setShowBlock] = useState(false);
  useEffect(() => {
    api.studioBookings(studio.id).then(setBookings).catch(() => undefined);
    api.blockedSlots(studio.id).then(setBlocked).catch(() => undefined);
  }, [studio.id]);
  const window_ = openingWindow(studio, new Date(day.getTime() + 12 * 3600_000));
  const dayBookings = bookings.filter((b) => sameDay(new Date(b.starts_at), day) && b.status !== "expired");
  const dayBlocks = blocked.filter((s) => sameDay(new Date(s.starts_at), day));
  async function unblock(slot: BlockedSlot) {
    try { await api.removeBlockedSlot(slot.id); setBlocked(blocked.filter((s) => s.id !== slot.id)); } catch (e) { toast(userMessage(e)); }
  }
  return (
    <main className="page">
      <LargeHead title="Calendar" eyebrow={Dates.weekdayDayMonth(day)} actions={<button className="icon-btn" onClick={() => setShowBlock(true)} aria-label={t("Block time")}><Ban size={18} /></button>} />
      <div className="split">
        <MonthCalendar selected={day} onSelect={setDay}
          marked={bookings.filter((b) => isActiveStatus(b.status) || b.status === "completed").map((b) => new Date(b.starts_at))}
          blocked={blocked.map((s) => new Date(s.starts_at))} />
        <div className="stack">
          <div className="row">
            <span className="grow"><GlowHead title={Dates.weekdayDay(day)} translate={false} count={dayBookings.length} /></span>
            <span className="chip caption semibold" style={{ cursor: "default" }}>
              {window_ ? <><Clock size={12} />{Dates.time(window_.start, studioZone(studio))}–{Dates.time(window_.end, studioZone(studio))}</> : <><Moon size={12} />{t("Closed")}</>}
            </span>
          </div>
          {dayBookings.length === 0 && dayBlocks.length === 0 && <Empty icon={Sparkles} title="Nothing booked" message={window_ ? "This day is wide open for sessions." : "The studio is closed this day."} />}
          {dayBookings.map((b) => (
            <button key={b.id} className="card tight row pressable" style={{ textAlign: "left", alignItems: "stretch" }} onClick={() => navigate(`/sessions/${b.id}`)}>
              <span style={{ width: 4, borderRadius: 4, background: "var(--neon)" }} /><span className="grow"><BookingRow booking={b} perspective="studio_owner" /></span>
            </button>
          ))}
          {dayBlocks.map((s) => (
            <div key={s.id} className="card tight row">
              <IconTile icon={Ban} size={34} colors={Tiles.danger} />
              <div className="grow"><div className="subhead semibold">{s.reason || t("Blocked")}</div><div className="caption secondary">{Dates.time(s.starts_at)} – {Dates.time(s.ends_at)}</div></div>
              <button className="pill" style={{ background: "color-mix(in srgb, var(--red) 15%, transparent)", color: "var(--red)", padding: "6px 10px" }} onClick={() => unblock(s)}>{t("Unblock")}</button>
            </div>
          ))}
        </div>
      </div>
      <BlockTimeSheet open={showBlock} onClose={() => setShowBlock(false)} studioId={studio.id} day={day} onAdded={(s) => setBlocked([...blocked, s])} />
    </main>
  );
}

function BlockTimeSheet({ open, onClose, studioId, day, onAdded }: { open: boolean; onClose: () => void; studioId: string; day: Date; onAdded: (s: BlockedSlot) => void }) {
  const toast = useToast();
  const [allDay, setAllDay] = useState(false);
  const [startDate, setStartDate] = useState(Dates.iso(day));
  const [startTime, setStartTime] = useState("12:00");
  const [endDate, setEndDate] = useState(Dates.iso(day));
  const [endTime, setEndTime] = useState("14:00");
  const [reason, setReason] = useState("");
  useEffect(() => { if (open) { setStartDate(Dates.iso(day)); setEndDate(Dates.iso(day)); } }, [open, day]);
  async function block() {
    const from = allDay ? new Date(`${startDate}T00:00`) : new Date(`${startDate}T${startTime}`);
    const to = allDay ? addDays(new Date(`${startDate}T00:00`), 1) : new Date(`${endDate}T${endTime}`);
    try {
      onAdded(await api.addBlockedSlot({ id: crypto.randomUUID(), studio_id: studioId, starts_at: from.toISOString(), ends_at: (to > from ? to : from).toISOString(), reason }));
      onClose();
    } catch (e) { toast(userMessage(e)); }
  }
  return (
    <Sheet open={open} onClose={onClose} title="Block time" closeLabel="Cancel" actions={<ToolButton title="Block" bold onClick={block} />}>
      <div className="stack-lg">
        <Section>
          <ToggleItem title="All day" checked={allDay} onChange={setAllDay} />
          <Item><span className="label">{t("From")}</span><input type="date" value={startDate} onChange={(e) => { setStartDate(e.target.value); if (endDate < e.target.value) setEndDate(e.target.value); }} />{!allDay && <input type="time" step={900} value={startTime} onChange={(e) => setStartTime(e.target.value)} />}</Item>
          {!allDay && <Item><span className="label">{t("To")}</span><input type="date" min={startDate} value={endDate} onChange={(e) => setEndDate(e.target.value)} /><input type="time" step={900} value={endTime} onChange={(e) => setEndTime(e.target.value)} /></Item>}
          <Item><input placeholder={t("Reason (private)")} value={reason} onChange={(e) => setReason(e.target.value)} /></Item>
        </Section>
        <button className="btn primary block" onClick={block}>{t("Block")}</button>
      </div>
    </Sheet>
  );
}

// MARK: Earnings

function Earnings() {
  const app = useApp();
  const studio = app.ownedStudio!;
  const { bookings, payouts, fees } = useStudioData(studio);
  const [invoices, setInvoices] = useState<FeeInvoice[]>([]);
  useEffect(() => { api.feeInvoices(studio.id).then(setInvoices).catch(() => undefined); }, [studio.id]);
  const s = earningsSummary(bookings, payouts);
  const money = (n: number, c = studio.currency) => Money.format(n, c);
  const max = Math.max(...s.monthly.map((m) => m.amount), 1);
  const isOverdue = (i: FeeInvoice) => i.status === "open" && !!i.due_at && new Date(i.due_at) < new Date();
  const invoiceTitle = (i: FeeInvoice) => (i.status === "paid" ? "Paid" : i.status === "collections" ? "Debt collection" : i.status === "void" ? "Cancelled" : isOverdue(i) ? "Overdue" : "Open");
  const overdue = invoices.some((i) => isOverdue(i) || i.status === "collections");
  return (
    <main className="page narrow">
      <PageHead title="Earnings" />
      <div className="stack-lg">
        <Section>
          <Item>
            <div className="stack" style={{ width: "100%", gap: 4 }}>
              <div className="caption secondary">{t("Earned this month")}</div>
              <div style={{ fontSize: 34, fontWeight: 700 }}>{money(s.netThisMonth)}</div>
              <div className="caption secondary">{format("%@ booked · %lld%% platform fee", money(s.grossThisMonth), Studios.feePercent(studio))}</div>
              <div className="row" style={{ alignItems: "flex-end", gap: 10, height: 160, marginTop: 12 }}>
                {s.monthly.map((m) => (
                  <div key={m.month.toISOString()} className="grow" style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, height: "100%", justifyContent: "flex-end" }}>
                    <div title={money(m.amount)} style={{ width: "60%", height: `${(m.amount / max) * 85}%`, minHeight: 2, background: "var(--accent)", borderRadius: 4 }} />
                    <span className="caption2 secondary">{Dates.monthShort(m.month)}</span>
                  </div>
                ))}
              </div>
            </div>
          </Item>
        </Section>
        <Section header="Totals">
          <Item><InfoRow icon={Sigma} title="All-time earnings" value={money(s.netAllTime)} /></Item>
          <Item><InfoRow icon={CircleCheck} title="Completed sessions" value={String(s.completedSessions)} /></Item>
          <Item><InfoRow icon={Clock} title="Hours booked" value={String(s.hoursBooked)} /></Item>
          <Item><InfoRow icon={Hourglass} title="Upcoming payouts" value={money(s.pendingPayout)} /></Item>
        </Section>
        <Section header="Payouts">
          {payouts.length === 0 && <Item><span className="secondary">{t("Payouts appear here after your first completed session.")}</span></Item>}
          {payouts.map((p) => (
            <Item key={p.id}>
              <div className="label"><div className="headline">{money(p.amount, p.currency)}</div><div className="caption secondary">{p.status === "paid" ? format("Paid %@", Dates.abbreviated(p.paid_at ?? p.scheduled_for)) : format("Expected %@", Dates.abbreviated(p.scheduled_for))}</div></div>
              <StatusPill text={PAYOUT_STATUS_TITLE[p.status]} color={p.status === "paid" ? C.positive : p.status === "failed" ? C.red : C.warning} />
            </Item>
          ))}
        </Section>
        <Section header="Cash bookings & platform fees" translate={false}
          footer={format("For cash bookings you collect the full price; EasySesh's %lld%% fee is deducted from your next payout. Anything left is invoiced monthly and must be paid within 14 days. Unpaid invoices lead to suspension from EasySesh and debt collection.", Studios.feePercent(studio))}>
          <Item><InfoRow icon={Banknote} title="Platform fees owed" value={money(Math.max(fees.reduce((n, f) => n + f.amount, 0), 0))} /></Item>
          {fees.map((f) => (
            <Item key={f.id}>
              <div className="label"><div>{t(FEE_KIND_TITLE[f.kind])}</div><div className="caption secondary">{Dates.abbreviated(f.created_at)}</div></div>
              <span style={{ color: f.amount < 0 ? "var(--positive)" : undefined }}>{money(f.amount, f.currency)}</span>
            </Item>
          ))}
        </Section>
        {invoices.length > 0 && (
          <Section header="Invoices" footerColor="var(--red)" footer={overdue ? "You have an overdue invoice. Pay it now to avoid suspension and debt collection. Contact support if you think this is a mistake." : undefined}>
            {invoices.map((i) => (
              <Item key={i.id}>
                <div className="label"><div className="headline">{money(i.amount, i.currency)}</div>{i.due_at && <div className="caption" style={{ color: isOverdue(i) ? "var(--red)" : "var(--text-2)" }}>{format("Due %@", Dates.abbreviated(i.due_at))}</div>}</div>
                {i.hosted_invoice_url && i.status !== "paid" && <a className="link-btn" href={i.hosted_invoice_url} target="_blank" rel="noreferrer">{t("Pay")}</a>}
                <StatusPill text={invoiceTitle(i)} color={i.status === "paid" ? C.positive : isOverdue(i) || i.status === "collections" ? C.red : C.warning} />
              </Item>
            ))}
          </Section>
        )}
        <Section>
          <NavItem to="/studio/payouts" title="Payout details" icon={Landmark} />
          <NavItem to="/legal/studio" title="Studio agreement" icon={FileText} />
        </Section>
      </div>
    </main>
  );
}

// MARK: Studio tab

function StudioSettings() {
  const app = useApp();
  const studio = app.ownedStudio!;
  useEffect(() => { api.ownedStudio().then((s) => s && app.setOwnedStudio(s)).catch(() => undefined); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const stat = (value: string, title: string) => <div className="grow center"><div className="headline heavy clamp-1">{value}</div><div className="caption2 secondary" style={{ fontWeight: 500 }}>{t(title)}</div></div>;
  return (
    <main className="page narrow">
      <LargeHead title="Studio" eyebrow="Your listing" />
      <div className="stack">
        <Link to={`/studios/${studio.id}`} className="pressable" style={{ display: "block" }}>
          <Photo url={studio.photo_urls[0]} style={{ aspectRatio: "16 / 10", borderRadius: 26, boxShadow: "0 20px 40px rgba(0,0,0,0.2)" }}>
            <div className="shade" />
            <span className="tag" style={{ position: "absolute", top: 12, right: 12, background: "rgba(0,0,0,0.35)", color: "#fff" }}><Eye size={12} />{t("Preview")}</span>
            <div style={{ position: "absolute", left: 16, bottom: 16, right: 16, color: "#fff" }} className="stack">
              <span className="tag" style={{ background: "rgba(0,0,0,0.35)", width: "fit-content", letterSpacing: "0.08em" }}><PulseDot color={C.positive} active={studio.is_active} />{t(studio.is_active ? "Live" : STUDIO_STATUS_TITLE[studio.status]).toUpperCase()}</span>
              {Studios.isPromoted(studio) && <PromotedTag />}
              <div className="row" style={{ gap: 6 }}><span style={{ fontSize: 22, fontWeight: 800 }} className="clamp-1">{studio.name}</span>{studio.is_verified && <VerifiedBadge />}{studio.has_admin_badge && <AdminBadge />}</div>
              <span className="subhead" style={{ opacity: 0.85 }}>{Studios.publicArea(studio)}</span>
            </div>
          </Photo>
        </Link>
        <div className="card tight row" style={{ gap: 0 }}>
          {stat(studio.review_count === 0 ? "–" : studio.rating_average.toFixed(1), "Rating")}
          <span style={{ width: 0.5, height: 30, background: "var(--stroke)" }} />
          {stat(String(studio.review_count), "Reviews")}
          <span style={{ width: 0.5, height: 30, background: "var(--stroke)" }} />
          {stat(String(studio.booking_count), "Bookings")}
          <span style={{ width: 0.5, height: 30, background: "var(--stroke)" }} />
          {stat(Money.format(studio.price_from, studio.currency), "From / h")}
        </div>
        <div className="grid-2">
          <TileLink to="/studio/edit" title="Edit profile" subtitle="Photos, gear, rooms" icon={Pencil} colors={Tiles.signal} />
          <TileLink to="/studio/edit/pricing" title="Prices" subtitle="Sessions & add-ons" icon={Tag} colors={Tiles.violet} />
          <TileLink to="/studio/edit/hours" title="Opening hours" subtitle="When you're bookable" icon={Clock} colors={Tiles.ocean} />
          <TileLink to="/studio/edit/policy" title="Booking settings" subtitle={studio.booking_policy.instant_book ? "Instant booking" : "You approve (24h)"} icon={Zap} colors={Tiles.warm} />
          <TileLink to="/studio/promotion" title="Promotion" subtitle={Studios.isPromoted(studio) ? "Promoted now" : "Not promoted"} icon={Megaphone} colors={Tiles.signal} />
          <TileLink to="/studio/artist-link" title="Artist profile" subtitle="Connect yours" icon={Link2} colors={Tiles.violet} />
          <TileLink to="/studio/payouts" title="Payouts" subtitle="Bank details" icon={Landmark} colors={Tiles.mint} />
          <TileLink to="/settings" title="Account" subtitle="Notifications & data" icon={CircleUserRound} colors={Tiles.muted} />
          <TileLink to="/settings/app" title="App settings" subtitle="Language, look, storage" icon={SlidersHorizontal} colors={Tiles.ocean} />
          <TileLink to="/support" title="Support" subtitle="Talk to EasySesh" icon={CircleHelp} colors={Tiles.warm} />
          <TileLink to="/legal/studio" title="Agreement" subtitle="Studio terms" icon={FileText} colors={Tiles.muted} />
        </div>
        <SignOutButton />
      </div>
    </main>
  );
}

