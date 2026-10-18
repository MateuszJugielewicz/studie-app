import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { loadStripe, type Stripe } from "@stripe/stripe-js";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import {
  Banknote, Building2, CalendarDays, CalendarPlus, Check, CircleAlert, Clock, Clock3, CreditCard, Hash, LocateFixed, LockKeyhole, TriangleAlert, AudioWaveform, CheckCircle2,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { config, PlatformConfig } from "../lib/config";
import {
  acceptsCash, availableSlots, Bookings, Dates, HOUR, Money, openingWindow, quote, studioZone, zonedTime, dayIn, type TimeSlot,
} from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { CANCELLATION, PAYMENT_STATUS_TITLE, PRICE_UNITS, type Booking, type Interval, type PriceBreakdown, type ServiceAddOn, type Studio } from "../lib/types";
import { InfoRow, Item, Loading, MonthCalendar, Notice, PageHead, Section, Segmented, Spinner, Stepper, Toggle, useToast } from "../components/ui";

let stripePromise: Promise<Stripe | null> | null = null;
export const getStripe = () => (stripePromise ??= config.stripePublishableKey ? loadStripe(config.stripePublishableKey) : Promise.resolve(null));

export default function BookingFlow() {
  const { studioId = "" } = useParams();
  const [params] = useSearchParams();
  const [studio, setStudio] = useState<Studio | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.studio(studioId).then(setStudio).catch((e) => setError(userMessage(e))); }, [studioId]);
  // Back from a payment method that opened another page (bank redirect, 3-D Secure).
  if (params.get("booking")) return <PaymentReturn bookingId={params.get("booking")!} />;
  if (error) return <main className="page narrow"><div className="card empty" style={{ marginTop: 40 }}>{error}</div></main>;
  if (!studio) return <Loading />;
  return <BookingDraft studio={studio} />;
}

interface Request { studio: Studio; sessionTypeId: string; start: Date; hours: number; addOns: Record<string, number>; notes: string }

function BookingDraft({ studio }: { studio: Studio }) {
  const zone = studioZone(studio);
  const [sessionTypeId, setSessionTypeId] = useState(studio.session_types[0]?.id ?? "");
  const sessionType = studio.session_types.find((s) => s.id === sessionTypeId);
  const [hours, setHours] = useState(studio.session_types[0]?.minimum_hours ?? 2);
  const [day, setDay] = useState(new Date());
  const [slot, setSlot] = useState<TimeSlot | null>(null);
  const [addOns, setAddOns] = useState<Record<string, number>>({});
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState<Interval[]>([]);
  const [loadingSlots, setLoadingSlots] = useState(true);
  const [checkout, setCheckout] = useState<Request | null>(null);

  // The chosen calendar day, as a day in the studio's time zone.
  const dayInstant = useMemo(() => zonedTime({ y: day.getFullYear(), m: day.getMonth() + 1, d: day.getDate() }, 12 * 60, zone), [day, zone]);
  useEffect(() => {
    setLoadingSlots(true);
    const start = new Date(dayInstant.getTime() - 36 * HOUR);
    api.busyIntervals([studio.id], start, new Date(start.getTime() + 72 * HOUR)).then((r) => setBusy(r[studio.id] ?? [])).catch(() => setBusy([])).finally(() => setLoadingSlots(false));
  }, [dayInstant, studio.id]);
  useEffect(() => { if (sessionType && hours < sessionType.minimum_hours) setHours(sessionType.minimum_hours); }, [sessionType, hours]);
  const slots = useMemo(() => availableSlots(studio, dayInstant, hours, busy), [studio, dayInstant, hours, busy]);
  useEffect(() => { setSlot((s) => (s && slots.some((x) => x.start.getTime() === s.start.getTime()) ? slots.find((x) => x.start.getTime() === s.start.getTime())! : null)); }, [slots]);
  const price = sessionType ? quote(studio, sessionType, hours, addOns) : null;
  const today = dayIn(new Date(), zone);
  const last = new Date(today.y, today.m - 1, today.d + studio.booking_policy.max_advance_days);

  if (checkout) return <Checkout request={checkout} onBack={() => setCheckout(null)} />;

  const continueButton = (
    <button className="btn primary block" disabled={!slot || !sessionType} onClick={() => slot && setCheckout({ studio, sessionTypeId, start: slot.start, hours, addOns, notes })}>
      {slot && price ? format("Continue · %@", Money.format(price.total, studio.currency)) : t("Pick a time")}
    </button>
  );

  return (
    <main className="page with-cta">
      <PageHead title={studio.name} translate={false} />
      <div className="two-col">
        <div className="stack-lg">
          <Section header="Session type">
            {studio.session_types.map((s) => (
              <Item key={s.id} onClick={() => setSessionTypeId(s.id)}>
                <span className="label">{s.name} · {Money.format(s.hourly_rate, studio.currency)}/h</span>
                {s.id === sessionTypeId && <Check size={18} color="var(--accent)" />}
              </Item>
            ))}
          </Section>
          <Section header="Duration">
            <Item><span className="label bold">{format("%lld hours", hours)}</span><Stepper value={hours} min={sessionType?.minimum_hours ?? 1} max={PlatformConfig.MAX_SESSION_HOURS} onChange={setHours} /></Item>
          </Section>
          <section className="section">
            <div className="section-header">{t("Date")}</div>
            <MonthCalendar selected={day} onSelect={(d) => { if (d <= last) setDay(d); }} min={new Date()} />
          </section>
          <Section header="Start time" footer={slot ? `${Dates.weekdayDayMonth(slot.start)} ${Dates.time(slot.start, zone)} – ${Dates.time(slot.end, zone)}` : undefined} translate={false}>
            <Item>
              {loadingSlots ? <Spinner /> : slots.length === 0 ? (
                <span className="secondary">{openingWindow(studio, dayInstant) == null ? t("The studio is closed this day.") : format("No free %lld-hour slots this day. Try fewer hours or another date.", hours)}</span>
              ) : (
                <div className="chips">
                  {slots.map((s) => {
                    const on = slot?.start.getTime() === s.start.getTime();
                    return <button key={s.start.toISOString()} onClick={() => setSlot(s)} className="subhead semibold" style={{ padding: "10px 18px", borderRadius: 10, background: on ? "var(--accent)" : "var(--bg)", color: on ? "#fff" : undefined }}>{Dates.time(s.start, zone)}</button>;
                  })}
                </div>
              )}
            </Item>
          </Section>
          {studio.add_ons.length > 0 && (
            <Section header="Add-ons">
              {studio.add_ons.map((a) => <AddOnRow key={a.id} addOn={a} currency={studio.currency} quantity={addOns[a.id] ?? 0} onChange={(q) => setAddOns({ ...addOns, [a.id]: q })} />)}
            </Section>
          )}
          <Section header="Notes for the studio">
            <Item><textarea rows={3} placeholder={t("What are you working on? Anything they should prepare?")} value={notes} onChange={(e) => setNotes(e.target.value)} /></Item>
          </Section>
          <div className="only-mobile">{price && <Section header="Price"><Item><PriceBreakdownView price={price} /></Item></Section>}</div>
        </div>
        <aside className="sticky stack hide-mobile">
          {price && <Section header="Price"><Item><PriceBreakdownView price={price} /></Item></Section>}
          {continueButton}
        </aside>
      </div>
      <div className="only-mobile mobile-cta">{continueButton}</div>
    </main>
  );
}

function AddOnRow({ addOn, currency, quantity, onChange }: { addOn: ServiceAddOn; currency: string; quantity: number; onChange: (q: number) => void }) {
  const perTrack = addOn.unit === "per_track";
  return (
    <Item>
      <div className="label">
        <div>{addOn.name}</div>
        <div className="caption secondary">{Money.format(addOn.price, currency)} {t(PRICE_UNITS.find(([k]) => k === addOn.unit)![1])}</div>
        {perTrack && quantity > 0 && <div className="caption accent">{quantity === 1 ? t("1 track") : format("%lld tracks", quantity)}</div>}
      </div>
      {perTrack ? <Stepper value={quantity} min={0} max={20} onChange={onChange} /> : <Toggle checked={quantity > 0} onChange={(on) => onChange(on ? 1 : 0)} label={addOn.name} />}
    </Item>
  );
}

export function PriceBreakdownView({ price }: { price: PriceBreakdown }) {
  const row = (title: string, amount: number, strong?: boolean) => (
    <div className={`row spread ${strong ? "bold" : ""}`}><span className={strong ? "" : "secondary"}>{t(title)}</span><span className={strong ? "" : "secondary"}>{Money.format(amount, price.currency)}</span></div>
  );
  return (
    <div className="stack" style={{ gap: 8, width: "100%" }}>
      <div className="row spread secondary"><span>{Money.format(price.hourly_rate, price.currency)} × {price.hours} h</span><span>{Money.format(price.session_amount, price.currency)}</span></div>
      {price.add_ons_amount > 0 && row("Add-ons", price.add_ons_amount)}
      {price.service_fee > 0 && row("Service fee", price.service_fee)}
      <div className="divider" />
      {row("Total", price.total, true)}
      {price.deposit_amount > 0 && <>{row("Due now (deposit + fee)", price.due_now)}{row("Charged after the session", price.due_later)}</>}
    </div>
  );
}

// MARK: Checkout

function Checkout({ request, onBack }: { request: Request; onBack: () => void }) {
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const { studio } = request;
  const zone = studioZone(studio);
  const sessionType = studio.session_types.find((s) => s.id === request.sessionTypeId)!;
  const cardAvailable = !!config.stripePublishableKey;
  const cashAvailable = acceptsCash(studio);
  const [cash, setCash] = useState(!cardAvailable && cashAvailable);
  const [agreed, setAgreed] = useState(false);
  const [working, setWorking] = useState(false);
  const [payment, setPayment] = useState<{ booking: Booking; clientSecret: string } | null>(null);
  const price = quote(studio, sessionType, request.hours, request.addOns);
  const amount = Money.format(price.due_now, price.currency);
  const instant = studio.booking_policy.instant_book;
  const payTitle = cash ? t(instant ? "Book · pay cash at the studio" : "Request to book · pay cash") : instant ? format("Pay %@", amount) : format("Request to book · %@", amount);
  const policy = CANCELLATION[studio.booking_policy.cancellation_policy];

  async function pay() {
    setWorking(true);
    try {
      const booking = await api.createBooking(studio.id, sessionType.id, request.start, request.hours, request.addOns, request.notes);
      if (cash) {
        const confirmed = await api.confirmCashBooking(booking.id);
        await app.refreshBadges();
        navigate(`/sessions/${confirmed.id}?new=1`, { replace: true });
      } else {
        const intent = await api.preparePayment(booking.id);
        setPayment({ booking, clientSecret: intent.client_secret });
      }
    } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }

  return (
    <main className="page">
      <PageHead title="Checkout" leading={<button className="tool-btn" onClick={onBack}>{t("Back")}</button>} />
      <div className="two-col">
        <div className="stack-lg">
          <Section header="Your session">
            <Item><InfoRow icon={Building2} title={studio.name} translate={false} /></Item>
            <Item><InfoRow icon={AudioWaveform} title={sessionType.name} value={`${request.hours} h`} translate={false} /></Item>
            <Item><InfoRow icon={CalendarDays} title={Dates.abbreviatedWithTime(request.start, zone).split(",")[0]} translate={false}
              value={`${Dates.time(request.start, zone)} – ${Dates.time(new Date(request.start.getTime() + request.hours * HOUR), zone)}`} /></Item>
          </Section>
          <Section header="Payment"><Item><PriceBreakdownView price={price} /></Item></Section>
          {cashAvailable && cardAvailable && !payment && (
            <Section header="How do you want to pay?" translate footer={cash ? format("Bring %@ in cash to your session. Paying in the app gives you automatic refunds under the cancellation policy.", Money.format(price.total, price.currency)) : undefined}>
              <div style={{ padding: 10 }}>
                <Segmented value={cash ? "cash" : "card"} onChange={(v) => setCash(v === "cash")} options={[{ value: "card", label: "Pay now in the app", icon: CreditCard }, { value: "cash", label: "Pay cash at the studio", icon: Banknote }]} />
              </div>
            </Section>
          )}
          <div className="card stack" style={{ gap: 8 }}>
            {cash ? (
              <>
                <Notice icon={Banknote} color="var(--text)">{format("Pay %@ in cash at the session.", Money.format(price.total, price.currency))}</Notice>
                <Notice icon={TriangleAlert} color="var(--warning)">{t("When you pay cash we cannot guarantee a refund, as EasySesh does not handle the cash. We will, however, look into it and try to help.")}</Notice>
              </>
            ) : cardAvailable ? (
              <Notice icon={LockKeyhole} color="var(--text)">{t("Card, Apple Pay or Google Pay – securely processed by Stripe.")}</Notice>
            ) : (
              <Notice icon={CircleAlert} color="var(--warning)">{t("In-app payment isn't available yet, and this studio doesn't accept cash. Message the studio to arrange your session.")}</Notice>
            )}
            {studio.booking_policy.check_in_enabled
              ? <Notice icon={LocateFixed} color="var(--text)">{t("Check in in the app when you arrive. EasySesh recommends it: it protects you against fraud and helps us sort out any problem.")}</Notice>
              : <Notice icon={TriangleAlert} color="var(--warning)">{t("This studio has turned off check-in. EasySesh can't promise a refund if something goes wrong with this session.")}</Notice>}
          </div>
          {!payment && (
            <Section footer={!instant ? (cash ? "This studio confirms requests manually, within 24 hours." : "This studio confirms requests manually, within 24 hours. Your card is authorised now and only charged if they accept.") : undefined}>
              <Item>
                <div className="label"><div className="footnote">{format("I agree to the studio's rules and the %@ cancellation policy.", t(policy.title).toLowerCase())}</div><div className="caption secondary">{t(policy.summary)}</div></div>
                <Toggle checked={agreed} onChange={setAgreed} />
              </Item>
            </Section>
          )}
        </div>
        <aside className="sticky stack">
          {payment ? (
            <Elements stripe={getStripe()} options={{ clientSecret: payment.clientSecret, appearance: stripeAppearance() }}>
              <PaymentForm booking={payment.booking} title={payTitle} />
            </Elements>
          ) : (
            <button className="btn primary block" disabled={!agreed || working || (!cash && !cardAvailable)} onClick={pay}>{working ? <Spinner /> : payTitle}</button>
          )}
        </aside>
      </div>
    </main>
  );
}

function stripeAppearance() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark" || (!document.documentElement.getAttribute("data-theme") && matchMedia("(prefers-color-scheme: dark)").matches);
  return { theme: dark ? "night" : "stripe", variables: { colorPrimary: dark ? "#FF3D8B" : "#E0246F", borderRadius: "12px" } } as const;
}

/** Stripe's payment form: card, Apple Pay, Google Pay and the local methods enabled in Stripe. */
function PaymentForm({ booking, title }: { booking: Booking; title: string }) {
  const stripe = useStripe();
  const elements = useElements();
  const toast = useToast();
  const app = useApp();
  const navigate = useNavigate();
  const [paying, setPaying] = useState(false);
  async function submit() {
    if (!stripe || !elements) return;
    setPaying(true);
    const { error } = await stripe.confirmPayment({
      elements, redirect: "if_required",
      confirmParams: { return_url: `${window.location.origin}/book/${booking.studio_id}?booking=${booking.id}` },
    });
    if (error) { toast(format("Payment failed: %@", error.message ?? "")); setPaying(false); return; }
    try {
      const confirmed = await api.confirmPayment(booking.id);
      await app.refreshBadges();
      navigate(`/sessions/${confirmed.id}?new=1`, { replace: true });
    } catch (e) { toast(userMessage(e)); }
    setPaying(false);
  }
  return (
    <div className="card stack">
      <PaymentElement options={{ layout: "tabs" }} />
      <button className="btn primary block" disabled={!stripe || paying} onClick={submit}>{paying ? <Spinner /> : title}</button>
    </div>
  );
}

function PaymentReturn({ bookingId }: { bookingId: string }) {
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.confirmPayment(bookingId).then((b) => navigate(`/sessions/${b.id}?new=1`, { replace: true })).catch((e) => setError(userMessage(e)));
  }, [bookingId, navigate]);
  return <main className="page narrow">{error ? <div className="card empty" style={{ marginTop: 40 }}>{error}</div> : <Loading />}</main>;
}

// MARK: Confirmation

/** Shown at the top of the booking page right after booking (iOS BookingConfirmationView). */
export function BookingConfirmation({ booking }: { booking: Booking }) {
  const confirmed = booking.status === "confirmed";
  const cash = Bookings.isCash(booking);
  const message = confirmed
    ? cash ? format("Pay %@ in cash at the studio. We'll remind you before your session.", Money.format(booking.price.total, booking.price.currency)) : t("We've sent a confirmation and receipt. We'll remind you before your session.")
    : format("%@ will respond within 24 hours.", booking.studio_name) + (cash ? "" : " " + t("You're only charged if they accept."));
  return (
    <div className="stack center" style={{ alignItems: "center", padding: "20px 0" }}>
      {confirmed ? <CheckCircle2 size={72} color="var(--positive)" /> : <Clock3 size={72} color="var(--warning)" />}
      <h1 className="title-l">{t(confirmed ? "You're booked!" : "Request sent")}</h1>
      <p className="secondary" style={{ margin: 0, maxWidth: 480 }}>{message}</p>
      <div className="card stack" style={{ width: "100%", maxWidth: 480, textAlign: "left", gap: 12 }}>
        <InfoRow icon={Hash} title="Reference" value={booking.reference} />
        <InfoRow icon={Building2} title={booking.studio_name} translate={false} />
        <InfoRow icon={CalendarDays} title={Dates.weekdayDayMonth(booking.starts_at)} translate={false} />
        <InfoRow icon={Clock} title={`${Dates.time(booking.starts_at)} – ${Dates.time(booking.ends_at)}`} translate={false} />
        <InfoRow icon={cash ? Banknote : CreditCard} title={PAYMENT_STATUS_TITLE[booking.payment_status]} value={Money.format(cash ? booking.price.total : booking.price.due_now, booking.price.currency)} />
      </div>
      <AddToCalendar booking={booking} />
    </div>
  );
}

export function AddToCalendar({ booking }: { booking: Booking }) {
  const [added, setAdded] = useState(false);
  function download() {
    const stamp = (d: string) => new Date(d).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
    const ics = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//EasySesh//EN", "BEGIN:VEVENT", `UID:${booking.id}@easysesh`, `DTSTAMP:${stamp(new Date().toISOString())}`,
      `DTSTART:${stamp(booking.starts_at)}`, `DTEND:${stamp(booking.ends_at)}`, `SUMMARY:${booking.session_type_name} · ${booking.studio_name}`,
      `DESCRIPTION:${format("EasySesh booking %@", booking.reference)}`, "END:VEVENT", "END:VCALENDAR",
    ].join("\r\n");
    const url = URL.createObjectURL(new Blob([ics], { type: "text/calendar" }));
    Object.assign(document.createElement("a"), { href: url, download: `easysesh-${booking.reference}.ics` }).click();
    URL.revokeObjectURL(url);
    setAdded(true);
  }
  return <button className="btn secondary" disabled={added} onClick={download}>{added ? <Check size={18} /> : <CalendarPlus size={18} />}{t(added ? "Added to calendar" : "Add to calendar")}</button>;
}
