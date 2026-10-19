import { useCallback, useEffect, useState } from "react";
import { Link, Route, Routes, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  Banknote, BadgeCheck, Building2, CalendarClock, CalendarDays, CheckCircle2, CircleCheck, Clock, Flag, Hash, History, LifeBuoy, LocateFixed, MapPin,
  MessageSquareText, MessagesSquare, Navigation, OctagonX, PlusCircle, Share, Sparkles, Star, TriangleAlert, Undo2, UserCheck, UserRound,
  XCircle, CreditCard, AudioWaveform, MessageCircleWarning,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { PlatformConfig } from "../lib/config";
import { availableSlots, Bookings as B, Dates, HOUR, isClosedStatus, Money, refundAmount, sameDay, studioZone, zonedTime, type TimeSlot } from "../lib/core";
import { format, t } from "../lib/i18n";
import { freshLocation, directionsUrl } from "../lib/location";
import { useApp, useLoad } from "../lib/state";
import {
  BOOKING_STATUS_TITLE, PAYMENT_METHOD_TITLE, PAYMENT_STATUS_TITLE, type Booking, type CancellationPolicy, type Interval, type PaymentTransaction, type Studio, type UserRole,
} from "../lib/types";
import {
  bookingStatusColor, Empty, GlowHead, IconTile, InfoRow, Item, ItemLabel, LargeHead, Loading, Logo, MonthCalendar, NavItem, Notice, PageHead,
  Section, Segmented, Sheet, StatusPill, Tiles, ToolButton, useToast,
} from "../components/ui";
import { RateArtistSheet, ReportSheet, WriteReviewSheet } from "../components/social";
import { AddToCalendar, BookingConfirmation, PriceBreakdownView } from "./BookingFlow";

export default function Bookings() {
  return (
    <Routes>
      <Route index element={<ArtistSessions />} />
      <Route path="history" element={<BookingHistory />} />
      <Route path=":id" element={<BookingDetail />} />
      <Route path=":id/receipt/:tx" element={<Receipt />} />
    </Routes>
  );
}

type Mode = "upcoming" | "calendar" | "past";

function ArtistSessions() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<Mode>("upcoming");
  const [day, setDay] = useState(new Date());
  const [reviewing, setReviewing] = useState<Booking | null>(null);
  const { data: bookings = [], loading, reload } = useLoad(() => api.artistBookings(), []);
  const upcoming = bookings.filter(B.isUpcoming).sort((a, b) => +new Date(a.starts_at) - +new Date(b.starts_at));
  const card = (b: Booking) => <button key={b.id} className="card tight pressable" style={{ textAlign: "left", display: "block", width: "100%" }} onClick={() => navigate(`/sessions/${b.id}`)}><BookingRow booking={b} perspective="artist" /></button>;

  return (
    <main className="page narrow">
      <LargeHead title="Sessions" eyebrow={upcoming.length ? format("%lld coming up", upcoming.length) : undefined} />
      <div className="stack">
        <Segmented value={mode} onChange={setMode} options={[{ value: "upcoming", label: "Upcoming", icon: Sparkles }, { value: "calendar", label: "Calendar", icon: CalendarDays }, { value: "past", label: "Past", icon: History }]} />
        {loading ? <Loading /> : mode === "upcoming" ? (
          upcoming.length ? upcoming.map(card) : <Empty icon={CalendarDays} title="No upcoming sessions" message="Find a studio and book your next session."><Link to="/studios" className="btn primary small">{t("Find a studio")}</Link></Empty>
        ) : mode === "calendar" ? (
          <>
            <MonthCalendar selected={day} onSelect={setDay} marked={bookings.filter((b) => !isClosedStatus(b.status) || b.status === "completed").map((b) => new Date(b.starts_at))} />
            {(() => {
              const list = bookings.filter((b) => sameDay(new Date(b.starts_at), day));
              return list.length ? list.map(card) : <div className="subhead secondary center" style={{ padding: 8 }}>{format("Nothing booked on %@.", Dates.abbreviated(day))}</div>;
            })()}
          </>
        ) : (
          <>
            {bookings.filter(B.canReview).length > 0 && (
              <>
                <GlowHead title="Waiting for your review" count={bookings.filter(B.canReview).length} />
                {bookings.filter(B.canReview).map((b) => (
                  <button key={b.id} className="card tight row pressable" style={{ textAlign: "left" }} onClick={() => setReviewing(b)}>
                    <IconTile icon={Star} size={38} />
                    <span className="grow"><div className="subhead semibold">{format("Review %@", b.studio_name)}</div><div className="caption secondary">{Dates.abbreviated(b.starts_at)}</div></span>
                  </button>
                ))}
              </>
            )}
            <GlowHead title="History" count={bookings.filter((b) => !B.isUpcoming(b)).length} />
            {bookings.filter((b) => !B.isUpcoming(b)).length === 0 ? <Empty icon={History} title="No past sessions" message="Sessions you've had show up here with receipts." /> : bookings.filter((b) => !B.isUpcoming(b)).map(card)}
          </>
        )}
      </div>
      {reviewing && <WriteReviewSheet open onClose={() => setReviewing(null)} booking={reviewing} onSubmitted={reload} />}
    </main>
  );
}

export function BookingRow({ booking, perspective }: { booking: Booking; perspective: UserRole }) {
  return (
    <div className="row" style={{ gap: 12, padding: "4px 0" }}>
      <div className="center" style={{ width: 48 }}>
        <div className="caption2 bold accent">{Dates.monthShort(booking.starts_at).toUpperCase()}</div>
        <div style={{ fontSize: 22, fontWeight: 700 }}>{Dates.day(booking.starts_at)}</div>
      </div>
      <div className="grow" style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <div className="headline clamp-1">{perspective === "artist" ? booking.studio_name : booking.artist_name}</div>
        <div className="subhead secondary clamp-1">{booking.session_type_name} · {Dates.time(booking.starts_at)}–{Dates.time(booking.ends_at)}</div>
        <div><StatusPill text={BOOKING_STATUS_TITLE[booking.status]} color={bookingStatusColor(booking.status)} /></div>
      </div>
      <div className="subhead bold">{Money.format(perspective === "artist" ? booking.price.total : booking.price.studio_payout, booking.price.currency)}</div>
    </div>
  );
}

function BookingHistory() {
  const { data: bookings = [], loading } = useLoad(() => api.artistBookings(), []);
  return (
    <main className="page narrow">
      <PageHead title="Booking history" />
      {loading ? <Loading /> : bookings.length === 0 ? <Empty icon={Clock} title="No bookings yet" /> : (
        <Section>{bookings.map((b) => <NavItem key={b.id} to={`/sessions/${b.id}`} title={b.studio_name} translate={false} value={Dates.abbreviated(b.starts_at)} />)}</Section>
      )}
    </main>
  );
}

// MARK: Detail

type SheetKind = "cancel" | "reschedule" | "review" | "dispute" | "decline" | "report" | "rate" | null;

export function BookingDetail() {
  const { id = "" } = useParams();
  const [params] = useSearchParams();
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const [booking, setBooking] = useState<Booking | null>(null);
  const [transactions, setTransactions] = useState<PaymentTransaction[]>([]);
  const [studio, setStudio] = useState<Studio | null>(null);
  const [sheet, setSheet] = useState<SheetKind>(null);
  const [working, setWorking] = useState(false);
  const [ratedArtist, setRatedArtist] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isStudio = app.account?.role === "studio_owner";

  const load = useCallback(async () => {
    try {
      const b = await api.booking(id);
      setBooking(b);
      setTransactions(await api.transactions(id));
      setStudio((s) => s ?? null);
      api.studio(b.studio_id).then(setStudio).catch(() => undefined);
      if (isStudio && b.status === "completed") api.artistReviews(b.artist_id).then((r) => setRatedArtist(r.some((x) => x.booking_id === b.id))).catch(() => undefined);
    } catch (e) { setError(userMessage(e)); }
  }, [id, isStudio]);
  useEffect(() => { load(); }, [load]);

  if (error) return <main className="page narrow"><PageHead title="Booking" /><div className="card">{error}</div></main>;
  if (!booking) return <Loading />;

  const work = async (action: () => Promise<void>) => {
    setWorking(true);
    try { await action(); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  };
  const amountPaid = transactions.filter((x) => x.status === "succeeded").reduce((n, x) => n + (x.kind === "refund" ? -x.amount : x.amount), 0);
  const feePercent = booking.price.subtotal > 0 ? Math.round((booking.price.studio_commission / booking.price.subtotal) * 100) : PlatformConfig.PLATFORM_FEE_PERCENT;
  const cash = B.isCash(booking);
  const checkInOff = studio?.booking_policy.check_in_enabled === false;
  const money = (n: number) => Money.format(n, booking.price.currency);
  async function message() {
    try { const c = await api.conversation(booking!.studio_id, booking!.id); navigate(`/messages/${c.id}`); } catch (e) { toast(userMessage(e)); }
  }
  async function checkIn() {
    await work(async () => { const p = await freshLocation(); setBooking(await api.checkIn(booking!.id, p?.latitude ?? null, p?.longitude ?? null)); });
  }

  const paymentFooter = cash
    ? isStudio
      ? format("Cash booking: collect %@ at the session. EasySesh's %lld%% fee is deducted from your next payout or invoiced.", money(booking.price.total), feePercent)
      : format("Pay %@ in cash at the studio.", money(booking.price.total)) + " " + t("When you pay cash we cannot guarantee a refund, as EasySesh does not handle the cash. We will, however, look into it and try to help.")
    : undefined;

  return (
    <main className="page narrow">
      <PageHead title={params.get("new") ? "" : "Booking"} backTo={params.get("new") ? (isStudio ? "/studio" : "/sessions") : undefined} />
      <div className="stack-lg">
        {params.get("new") && <BookingConfirmation booking={booking} />}
        <Section>
          <Item>
            <div className="stack" style={{ gap: 6 }}>
              <div><StatusPill text={BOOKING_STATUS_TITLE[booking.status]} color={bookingStatusColor(booking.status)} /></div>
              <div className="title-m">{isStudio ? booking.artist_name : booking.studio_name}</div>
              <div className="secondary">{format("%@ · %lld hours", booking.session_type_name, booking.hours)}</div>
            </div>
          </Item>
          <Item><InfoRow icon={CalendarDays} title={Dates.weekdayDayMonth(booking.starts_at)} translate={false} /></Item>
          <Item><InfoRow icon={Clock} title={`${Dates.time(booking.starts_at)} – ${Dates.time(booking.ends_at)}`} translate={false} /></Item>
          <Item><InfoRow icon={Hash} title="Reference" value={booking.reference} /></Item>
          {studio && !isStudio && booking.status === "confirmed" && <Item><InfoRow icon={MapPin} title={[studio.address.street, [studio.address.postal_code, studio.address.city].filter(Boolean).join(" "), studio.address.country].filter(Boolean).join(", ")} translate={false} /></Item>}
          {booking.notes && <Item><InfoRow icon={MessageSquareText} title={booking.notes} translate={false} /></Item>}
          {booking.add_ons.map((a) => <Item key={a.id}><InfoRow icon={PlusCircle} title={a.quantity > 1 ? `${a.name} × ${a.quantity}` : a.name} value={money(a.amount)} translate={false} /></Item>)}
          {booking.cancellation_reason && <Item><InfoRow icon={XCircle} title="Reason" value={booking.cancellation_reason} /></Item>}
        </Section>

        {["confirmed", "completed", "disputed"].includes(booking.status) && (
          <Section header="Check-in" footer={!checkInOff && !booking.artist_checked_in_at && booking.status === "confirmed"
            ? (isStudio ? "Checking in records that the artist arrived. It protects both of you against fraud and helps EasySesh settle disputes."
              : "EasySesh recommends checking in when you arrive. It protects you against fraud and helps us settle any dispute. Your location is only used if you allow it.") : undefined}>
            {booking.artist_checked_in_at ? (
              <Item>
                <IconTile icon={BadgeCheck} size={34} colors={Tiles.mint} />
                <div className="label">
                  <div className="subhead semibold">{t(isStudio ? "Artist checked in" : "You checked in")}</div>
                  <div className="caption secondary">{booking.artist_check_in_distance_m != null
                    ? format("%@ · %@ from the studio", Dates.abbreviatedWithTime(booking.artist_checked_in_at), booking.artist_check_in_distance_m < 1000 ? `${booking.artist_check_in_distance_m} m` : `${(booking.artist_check_in_distance_m / 1000).toFixed(1)} km`)
                    : Dates.abbreviatedWithTime(booking.artist_checked_in_at)}</div>
                </div>
              </Item>
            ) : checkInOff ? (
              <Item><Notice icon={TriangleAlert} color="var(--warning)">{t(isStudio ? "Check-in is turned off for your studio. EasySesh can't promise the artist a refund if something goes wrong." : "This studio has turned off check-in. EasySesh can't promise a refund if something goes wrong with this session.")}</Notice></Item>
            ) : !isStudio && B.canCheckIn(booking) ? (
              <Item onClick={working ? undefined : checkIn}>
                <IconTile icon={LocateFixed} size={34} />
                <div className="label"><div className="headline">{t("Check in")}</div><div className="caption secondary">{t("Tap when you've arrived at the studio")}</div></div>
              </Item>
            ) : booking.status === "confirmed" ? (
              <Item><Notice icon={Clock}>{t(isStudio ? "The artist hasn't checked in yet." : "Check-in opens 1 hour before your session.")}</Notice></Item>
            ) : null}
            {booking.studio_confirmed_arrival_at ? (
              <Item><Notice icon={UserCheck} color="var(--text)">{format(isStudio ? "You confirmed the artist arrived · %@" : "The studio confirmed you arrived · %@", Dates.time(booking.studio_confirmed_arrival_at))}</Notice></Item>
            ) : isStudio && booking.status === "confirmed" && new Date(booking.starts_at).getTime() - HOUR <= Date.now() ? (
              <Item onClick={() => work(async () => setBooking(await api.confirmArrival(booking.id)))}><ItemLabel title="Confirm the artist arrived" icon={UserCheck} color="var(--accent)" /></Item>
            ) : null}
          </Section>
        )}

        {isStudio && booking.status === "pending_approval" && (
          <Section footer={cash ? "The artist will pay cash at the session." : "The artist's card is authorised. Accepting charges it; declining releases the hold."}>
            <Item onClick={working ? undefined : () => work(async () => { setBooking(await api.respondToBooking(booking.id, true, null)); setTransactions(await api.transactions(booking.id)); app.refreshBadges(); })}>
              <ItemLabel title="Accept booking" icon={CheckCircle2} color="var(--accent)" />
            </Item>
            <Item onClick={() => setSheet("decline")}><ItemLabel title="Decline" icon={XCircle} color="var(--red)" /></Item>
          </Section>
        )}

        <Section header="Actions">
          <Item onClick={message}><ItemLabel title={isStudio ? "Message artist" : "Message studio"} icon={MessagesSquare} color="var(--accent)" /></Item>
          {isStudio ? (
            <>
              <NavItem to={`/artists/${booking.artist_id}`} title="View artist profile" icon={UserRound} />
              {booking.status === "completed" && !ratedArtist && <Item onClick={() => setSheet("rate")}><ItemLabel title="Rate the artist" icon={Star} color="var(--accent)" /></Item>}
            </>
          ) : <NavItem to={`/studios/${booking.studio_id}`} title="View studio" icon={Building2} />}
          {studio && !isStudio && booking.status === "confirmed" && <Item onClick={() => window.open(directionsUrl(studio), "_blank")}><ItemLabel title="Directions" icon={Navigation} color="var(--accent)" /></Item>}
          {B.canReschedule(booking) && <Item onClick={() => setSheet("reschedule")}><ItemLabel title="Change date or time" icon={CalendarClock} color="var(--accent)" /></Item>}
          {!isStudio && B.canReview(booking) && <Item onClick={() => setSheet("review")}><ItemLabel title="Write a review" icon={Star} color="var(--accent)" /></Item>}
          {B.canCancel(booking) && <Item onClick={() => setSheet("cancel")}><ItemLabel title="Cancel booking" icon={OctagonX} color="var(--red)" /></Item>}
          {["confirmed", "completed"].includes(booking.status) && <Item onClick={() => setSheet("dispute")}><ItemLabel title="Report a problem" icon={MessageCircleWarning} color="var(--accent)" /></Item>}
          <Item onClick={() => setSheet("report")}><ItemLabel title={isStudio ? "Report artist" : "Report studio"} icon={Flag} color="var(--accent)" /></Item>
          <NavItem to={`/support?booking=${booking.id}`} title="Contact EasySesh support" icon={LifeBuoy} />
        </Section>

        <Section header="Payment" footer={paymentFooter} translate={false}>
          <Item>
            {isStudio ? (
              <div className="stack" style={{ gap: 8, width: "100%" }}>
                {(booking.price.discounts ?? []).filter((d) => d.kind !== "easysesh_code").length > 0 && <>
                  <div className="row spread secondary"><span>{t("Before discounts")}</span><span>{money(booking.price.original_subtotal ?? booking.price.subtotal)}</span></div>
                  {(booking.price.discounts ?? []).filter((d) => d.kind !== "easysesh_code").map((d, i) => (
                    <div key={i} className="row spread secondary"><span>{d.kind === "offer" ? d.label : format("Code %@", d.label)} (−{d.percent}%)</span><span>{money(-d.amount)}</span></div>
                  ))}
                </>}
                <div className="row spread secondary"><span>{t("Session price")}</span><span>{money(booking.price.subtotal)}</span></div>
                <div className="row spread secondary"><span>{format("EasySesh platform fee (%lld%%)", feePercent)}</span><span>{money(-booking.price.studio_commission)}</span></div>
                <div className="row spread bold"><span>{t(cash ? "Yours to keep" : "Your payout")}</span><span>{money(booking.price.studio_payout)}</span></div>
                {(booking.price.discounts ?? []).some((d) => d.kind === "easysesh_code") && (
                  <div className="caption secondary">{t("The artist used an EasySesh promo code. EasySesh pays that discount – your payout isn't affected.")}</div>
                )}
              </div>
            ) : <PriceBreakdownView price={booking.price} />}
          </Item>
          <Item><InfoRow icon={cash ? Banknote : CreditCard} title="Status" value={t(PAYMENT_STATUS_TITLE[booking.payment_status])} /></Item>
          {isStudio && cash && booking.payment_status === "pay_at_studio" && new Date(booking.starts_at).getTime() <= Date.now() && ["confirmed", "completed"].includes(booking.status) && (
            <Item onClick={working ? undefined : () => work(async () => setBooking(await api.markCashReceived(booking.id)))}><ItemLabel title="Mark cash as received" icon={CircleCheck} color="var(--accent)" /></Item>
          )}
          {booking.refund_amount > 0 && <Item><InfoRow icon={Undo2} title="Refunded" value={money(booking.refund_amount)} /></Item>}
        </Section>

        {transactions.length > 0 && (
          <Section header="Receipts">
            {transactions.map((x) => (
              <Item key={x.id} to={`/sessions/${booking.id}/receipt/${x.id}`}>
                <div className="label"><div>{t(x.kind === "refund" ? "Refund" : x.kind === "balance" ? "Balance payment" : "Payment")}</div><div className="caption secondary">{Dates.abbreviatedWithTime(x.created_at)}</div></div>
                <span style={{ color: x.kind === "refund" ? "var(--positive)" : undefined }}>{x.kind === "refund" ? "−" : ""}{Money.format(x.amount, x.currency)}</span>
              </Item>
            ))}
          </Section>
        )}
        {!params.get("new") && B.isUpcoming(booking) && <div><AddToCalendar booking={booking} /></div>}
      </div>

      <CancelSheet open={sheet === "cancel"} onClose={() => setSheet(null)} booking={booking} policy={studio?.booking_policy.cancellation_policy ?? "moderate"} amountPaid={amountPaid} isStudio={isStudio} onCancelled={(b) => { setBooking(b); load(); }} />
      {studio && <RescheduleSheet open={sheet === "reschedule"} onClose={() => setSheet(null)} booking={booking} studio={studio} onChanged={setBooking} />}
      <WriteReviewSheet open={sheet === "review"} onClose={() => setSheet(null)} booking={booking} onSubmitted={() => setBooking({ ...booking, has_review: true })} />
      <TextPromptSheet open={sheet === "dispute"} onClose={() => setSheet(null)} title="Report a problem" placeholder="What went wrong? Our team will review the booking and contact both sides." action="Send"
        onSubmit={async (text) => { await api.openDispute(booking.id, text); setBooking({ ...booking, status: "disputed" }); }} />
      <TextPromptSheet open={sheet === "decline"} onClose={() => setSheet(null)} title="Decline request" placeholder="Optional message to the artist" action="Decline" allowEmpty
        onSubmit={async (text) => { setBooking(await api.respondToBooking(booking.id, false, text || null)); app.refreshBadges(); }} />
      <ReportSheet open={sheet === "report"} onClose={() => setSheet(null)} target={isStudio ? "user" : "studio"} targetId={isStudio ? booking.artist_id : booking.studio_id} />
      <RateArtistSheet open={sheet === "rate"} onClose={() => setSheet(null)} booking={booking} onSubmitted={() => setRatedArtist(true)} />
    </main>
  );
}

function CancelSheet({ open, onClose, booking, policy, amountPaid, isStudio, onCancelled }: {
  open: boolean; onClose: () => void; booking: Booking; policy: CancellationPolicy; amountPaid: number; isStudio: boolean; onCancelled: (b: Booking) => void;
}) {
  const toast = useToast();
  const [reason, setReason] = useState("");
  const [working, setWorking] = useState(false);
  const refund = booking.payment_status === "authorized" ? booking.price.due_now : refundAmount(booking.price, amountPaid, policy, booking.starts_at, isStudio ? "studio_owner" : "artist");
  const titles = { flexible: "Flexible", moderate: "Moderate", strict: "Strict" };
  const summaries = { flexible: "Full refund up to 24 hours before the session.", moderate: "Full refund up to 72 hours before, 50% up to 24 hours before.", strict: "50% refund up to 7 days before the session. No refund after that." };
  async function cancel() {
    setWorking(true);
    try { onCancelled(await api.cancelBooking(booking.id, reason)); onClose(); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  const money = (n: number) => Money.format(n, booking.price.currency);
  return (
    <Sheet open={open} onClose={onClose} title="Cancel booking" closeLabel="Keep booking">
      <div className="stack-lg">
        <Section translate={false} footer={isStudio ? t("When a studio cancels, the artist always gets a full refund. Frequent cancellations affect your listing.") : format("%@ policy: %@", t(titles[policy]), t(summaries[policy]))}>
          <Item><div className="stack" style={{ gap: 8, width: "100%" }}>
            <div className="row spread secondary"><span>{t("Paid so far")}</span><span>{money(booking.payment_status === "authorized" ? 0 : amountPaid)}</span></div>
            <div className="row spread bold"><span>{t(isStudio ? "Artist is refunded" : "You'll get back")}</span><span>{money(refund)}</span></div>
          </div></Item>
        </Section>
        <Section header="Reason"><Item><textarea rows={3} placeholder={t(isStudio ? "Let the artist know why" : "Optional")} value={reason} onChange={(e) => setReason(e.target.value)} /></Item></Section>
        <button className="btn danger block" disabled={working || (isStudio && !reason)} onClick={cancel}>{t("Cancel booking")}</button>
      </div>
    </Sheet>
  );
}

function RescheduleSheet({ open, onClose, booking, studio, onChanged }: { open: boolean; onClose: () => void; booking: Booking; studio: Studio; onChanged: (b: Booking) => void }) {
  const toast = useToast();
  const zone = studioZone(studio);
  const [day, setDay] = useState(new Date(booking.starts_at));
  const [busy, setBusy] = useState<Interval[]>([]);
  const [selected, setSelected] = useState<TimeSlot | null>(null);
  const dayInstant = zonedTime({ y: day.getFullYear(), m: day.getMonth() + 1, d: day.getDate() }, 720, zone);
  useEffect(() => {
    if (!open) return;
    setSelected(null);
    api.busyIntervals([studio.id], new Date(dayInstant.getTime() - 36 * HOUR), new Date(dayInstant.getTime() + 36 * HOUR)).then((r) => setBusy(r[studio.id] ?? [])).catch(() => setBusy([]));
  }, [open, day]); // eslint-disable-line react-hooks/exhaustive-deps
  // The booking itself doesn't block its own new time.
  const own = { start: +new Date(booking.starts_at), end: +new Date(booking.ends_at) };
  const slots = availableSlots(studio, dayInstant, booking.hours, busy.filter((b) => !(b.start.getTime() === own.start && b.end.getTime() === own.end)));
  async function save() {
    if (!selected) return;
    try { onChanged(await api.rescheduleBooking(booking.id, selected.start)); onClose(); } catch (e) { toast(userMessage(e)); }
  }
  return (
    <Sheet open={open} onClose={onClose} title="Change booking" closeLabel="Cancel" actions={<ToolButton title="Save" bold disabled={!selected} onClick={save} />}>
      <div className="stack-lg">
        <section className="section">
          <MonthCalendar selected={day} onSelect={setDay} min={new Date()} />
          <div className="section-footer">{format("Same session type and length (%lld h). To change the length, cancel and book again.", booking.hours)}</div>
        </section>
        <Section header="New start time">
          <Item>
            {slots.length === 0 ? <span className="secondary">{t("No free slots this day.")}</span> : (
              <div className="chips">{slots.map((s) => {
                const on = selected?.start.getTime() === s.start.getTime();
                return <button key={s.start.toISOString()} onClick={() => setSelected(s)} className="subhead semibold" style={{ padding: "9px 16px", borderRadius: 10, background: on ? "var(--accent)" : "var(--fill)", color: on ? "#fff" : undefined }}>{Dates.time(s.start, zone)}</button>;
              })}</div>
            )}
          </Item>
        </Section>
        <button className="btn primary block" disabled={!selected} onClick={save}>{t("Save")}</button>
      </div>
    </Sheet>
  );
}

export function TextPromptSheet({ open, onClose, title, placeholder, action, allowEmpty, onSubmit }: {
  open: boolean; onClose: () => void; title: string; placeholder: string; action: string; allowEmpty?: boolean; onSubmit: (text: string) => Promise<void>;
}) {
  const toast = useToast();
  const [text, setText] = useState("");
  const [working, setWorking] = useState(false);
  const ok = !working && (allowEmpty || text.trim().length >= 5);
  async function submit() {
    setWorking(true);
    try { await onSubmit(text.trim()); setText(""); onClose(); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  return (
    <Sheet open={open} onClose={onClose} title={title} closeLabel="Cancel" actions={<ToolButton title={action} bold disabled={!ok} onClick={submit} />}>
      <div className="stack-lg">
        <Section><Item><textarea rows={5} placeholder={t(placeholder)} value={text} onChange={(e) => setText(e.target.value)} /></Item></Section>
        <button className="btn primary block" disabled={!ok} onClick={submit}>{t(action)}</button>
      </div>
    </Sheet>
  );
}

function Receipt() {
  const { id = "", tx = "" } = useParams();
  const { data } = useLoad(async () => ({ booking: await api.booking(id), transactions: await api.transactions(id) }), [id]);
  if (!data) return <Loading />;
  const { booking } = data;
  const transaction = data.transactions.find((x) => x.id === tx);
  if (!transaction) return <Loading />;
  const refund = transaction.kind === "refund";
  const method = [t(PAYMENT_METHOD_TITLE[transaction.method]), transaction.card_brand, transaction.card_last4 ? `•••• ${transaction.card_last4}` : null].filter(Boolean).join(" ");
  return (
    <main className="page narrow">
      <PageHead title="Receipt" actions={<button className="icon-btn" onClick={() => window.print()} aria-label={t("Share receipt")}><Share size={18} /></button>} />
      <div className="stack-lg">
        <div className="stack center" style={{ alignItems: "center", gap: 6 }}>
          <Logo size={20} />
          <div className="headline">{t(refund ? "Refund receipt" : "Payment receipt")}</div>
          <div style={{ fontSize: 40, fontWeight: 800 }}>{Money.format(transaction.amount, transaction.currency)}</div>
        </div>
        <Section>
          <Item><InfoRow icon={Hash} title="Receipt no." value={transaction.receipt_number} /></Item>
          <Item><InfoRow icon={CalendarDays} title="Date" value={Dates.abbreviatedWithTime(transaction.created_at)} /></Item>
          <Item><InfoRow icon={CreditCard} title="Method" value={method} /></Item>
          <Item><InfoRow icon={CheckCircle2} title="Status" value={transaction.status} /></Item>
        </Section>
        <Section header="Booking">
          <Item><InfoRow icon={Building2} title={booking.studio_name} translate={false} /></Item>
          <Item><InfoRow icon={AudioWaveform} title={booking.session_type_name} value={`${booking.hours} h`} translate={false} /></Item>
          <Item><InfoRow icon={CalendarDays} title={Dates.abbreviatedWithTime(booking.starts_at)} translate={false} /></Item>
          <Item><InfoRow icon={Hash} title="Reference" value={booking.reference} /></Item>
        </Section>
        {transaction.kind === "charge" && <Section header="Breakdown"><Item><PriceBreakdownView price={booking.price} /></Item></Section>}
        <Section footer="EasySesh acts as payment agent for the studio. The service fee includes VAT where applicable.">
          <Item onClick={() => window.print()}><ItemLabel title="Share receipt" icon={Share} color="var(--accent)" /></Item>
        </Section>
      </div>
    </main>
  );
}
