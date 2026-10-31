// Business logic shared with the apps (ios/EasySesh/Core, android/.../core): prices, refunds,
// availability, search, validation and earnings.
import { PlatformConfig } from "./config";
import { format, locale, t } from "./i18n";
import type {
  Booking, BookingStatus, CancellationPolicy, Interval, OpeningHours, Payout, PriceBreakdown, ServiceAddOn, SessionType,
  SocialLink, Studio, UserRole, BookedAddOn, Genre, Facility, EquipmentCategory, PriceRule, RateLine, VolumePrice, DayRate,
} from "./types";
import { genreTitle } from "./types";

// MARK: Money & distance

/** Random v4 UUID. crypto.randomUUID only exists on https pages, so fall back to getRandomValues. */
export function uuid(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export const Money = {
  /** Formats minor units: 1500 EUR → "€15", 1550 → "€15.50". */
  format(minor: number, currency: string): string {
    const whole = minor % 100 === 0;
    try {
      return new Intl.NumberFormat(locale(), {
        style: "currency", currency: currency.toUpperCase(),
        minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: whole ? 0 : 2,
      }).format(minor / 100);
    } catch {
      return `${(minor / 100).toFixed(whole ? 0 : 2)} ${currency}`;
    }
  },
  /** "15", "15.5" or "15,50" → minor units. */
  parse(text: string): number | null {
    const value = Number(text.replace(",", ".").trim());
    if (!text.trim() || Number.isNaN(value) || value < 0) return null;
    return Math.round(value * 100);
  },
  percent: (amount: number, percent: number) => Math.floor((amount * percent + 50) / 100),
  editable: (minor: number) => (minor % 100 === 0 ? String(minor / 100) : (minor / 100).toFixed(2)),
};

export function formatDistance(meters: number, metric = true): string {
  const n = (value: number) => new Intl.NumberFormat(locale(), { maximumFractionDigits: 1, minimumFractionDigits: 1 }).format(value);
  if (metric) return meters < 1000 ? `${Math.round(meters / 10) * 10} m` : `${n(meters / 1000)} km`;
  return `${n(meters / 1609.344)} mi`;
}

export interface GeoPoint { latitude: number; longitude: number }

export function distanceMeters(a: GeoPoint, b: GeoPoint): number {
  const r = 6_371_000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLon = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}

// MARK: Dates

export const HOUR = 3_600_000;
export const DAY = 86_400_000;

/** Offset of `zone` from UTC at `date`, in minutes. */
function zoneOffset(date: Date, zone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  const asUtc = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return Math.round((asUtc - date.getTime()) / 60_000);
}

/** A calendar date (year, month 1-12, day) in a time zone. */
export interface DayKey { y: number; m: number; d: number }

export function dayIn(date: Date, zone: string): DayKey {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "numeric", day: "numeric" }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return { y: get("year"), m: get("month"), d: get("day") };
}

/** The instant of `minutes` after midnight on `day` in `zone`. */
export function zonedTime(day: DayKey, minutes: number, zone: string): Date {
  const guess = Date.UTC(day.y, day.m - 1, day.d, 0, minutes);
  let offset = zoneOffset(new Date(guess), zone);
  let result = guess - offset * 60_000;
  const second = zoneOffset(new Date(result), zone);
  if (second !== offset) { offset = second; result = guess - offset * 60_000; }
  return new Date(result);
}

export const localZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;
export const studioZone = (s: Studio) => s.timezone || localZone();
export const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
export const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
export const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
export const weekdayOf = (date: Date, zone: string) => {
  const k = dayIn(date, zone);
  return new Date(Date.UTC(k.y, k.m - 1, k.d)).getUTCDay() + 1; // 1 = Sunday
};

export const Dates = {
  abbreviated: (d: string | Date) => new Intl.DateTimeFormat(locale(), { dateStyle: "medium" }).format(new Date(d)),
  abbreviatedWithTime: (d: string | Date, zone?: string) =>
    new Intl.DateTimeFormat(locale(), { dateStyle: "medium", timeStyle: "short", timeZone: zone }).format(new Date(d)),
  time: (d: string | Date, zone?: string) => new Intl.DateTimeFormat(locale(), { timeStyle: "short", timeZone: zone }).format(new Date(d)),
  weekdayDayMonth: (d: string | Date) => cap(new Intl.DateTimeFormat(locale(), { weekday: "long", day: "numeric", month: "long" }).format(new Date(d))),
  weekdayDay: (d: string | Date) => cap(new Intl.DateTimeFormat(locale(), { weekday: "long", day: "numeric" }).format(new Date(d))),
  weekdayShort: (d: string | Date) => cap(new Intl.DateTimeFormat(locale(), { weekday: "short" }).format(new Date(d))),
  weekdayShortDay: (d: string | Date) => cap(new Intl.DateTimeFormat(locale(), { weekday: "short", day: "numeric" }).format(new Date(d))),
  monthShort: (d: string | Date) => new Intl.DateTimeFormat(locale(), { month: "short" }).format(new Date(d)),
  monthYear: (d: string | Date) => cap(new Intl.DateTimeFormat(locale(), { month: "long", year: "numeric" }).format(new Date(d))),
  day: (d: string | Date) => String(new Date(d).getDate()),
  relative(d: string | Date): string {
    const seconds = (Date.now() - new Date(d).getTime()) / 1000;
    const rtf = new Intl.RelativeTimeFormat(locale(), { numeric: "auto" });
    if (seconds < 60) return t("now");
    if (seconds < 3600) return rtf.format(-Math.round(seconds / 60), "minute");
    if (seconds < 86_400) return rtf.format(-Math.round(seconds / 3600), "hour");
    if (seconds < 7 * 86_400) return rtf.format(-Math.round(seconds / 86_400), "day");
    return Dates.abbreviated(d);
  },
  /** "yyyy-mm-dd" for <input type=date>. */
  iso: (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`,
};

function cap(s: string) { return s.charAt(0).toLocaleUpperCase(locale()) + s.slice(1); }

export function formatMinutes(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

export function weekdayName(weekday: number): string {
  // 2026-10-18 is a Sunday (weekday 1).
  const date = new Date(Date.UTC(2026, 9, 17 + weekday));
  return cap(new Intl.DateTimeFormat(locale(), { weekday: "long", timeZone: "UTC" }).format(date));
}

export const OPENING_DISPLAY_ORDER = [2, 3, 4, 5, 6, 7, 1];

export function weekdayShort(weekday: number): string {
  const date = new Date(Date.UTC(2026, 9, 17 + weekday));
  return cap(new Intl.DateTimeFormat(locale(), { weekday: "short", timeZone: "UTC" }).format(date)).replace(/\.$/, "");
}

/** "Mon–Fri · 18:00–24:00" for a time-based price. */
export function priceRuleSummary(rule: PriceRule): string {
  const days = OPENING_DISPLAY_ORDER.filter((d) => rule.weekdays.includes(d));
  // Consecutive days (Mon → Sun order) become ranges.
  const runs: number[][] = [];
  for (const d of days) {
    const last = runs[runs.length - 1];
    if (last && OPENING_DISPLAY_ORDER.indexOf(d) === OPENING_DISPLAY_ORDER.indexOf(last[last.length - 1]) + 1) last.push(d); else runs.push([d]);
  }
  const dayText = days.length === 7 ? t("Every day") : runs.map((r) => (r.length > 2 ? `${weekdayShort(r[0])}–${weekdayShort(r[r.length - 1])}` : r.map(weekdayShort).join(", "))).join(", ");
  const time = (m: number) => (m >= 1440 ? "24:00" : formatMinutes(m));
  const timeText = rule.from === 0 && rule.to >= 1440 ? t("All day") : `${time(rule.from)}–${time(rule.to)}`;
  return `${dayText} · ${timeText}`;
}
export const STANDARD_WEEK: OpeningHours[] = [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, is_closed: false, opens_at: 600, closes_at: 1320 }));
export const hoursLabel = (h: OpeningHours) => (h.is_closed ? t("Closed") : `${formatMinutes(h.opens_at)} – ${formatMinutes(h.closes_at)}`);

// MARK: Studio helpers

export const Studios = {
  feePercent: (s: Studio) => s.platform_fee_percent ?? PlatformConfig.PLATFORM_FEE_PERCENT,
  isPromoted: (s: Studio) => !!s.promoted_until && new Date(s.promoted_until).getTime() > Date.now(),
  isBookable: (s: Studio) => s.status === "approved" && s.is_active,
  offersMixing: (s: Studio) => s.add_ons.some((a) => a.kind === "mixing"),
  offersMastering: (s: Studio) => s.add_ons.some((a) => a.kind === "mastering"),
  publicArea: (s: Studio) => [s.address.area, s.address.city].filter(Boolean).join(", "),
  singleLine: (s: Studio) => [s.address.street, [s.address.postal_code, s.address.city].filter(Boolean).join(" "), s.address.country].filter(Boolean).join(", "),
  hours: (s: Studio, weekday: number) => s.opening_hours.find((h) => h.weekday === weekday),
  normalized: (s: Studio): Studio => ({ ...s, price_from: s.session_types.length ? Math.min(...s.session_types.map((x) => x.hourly_rate)) : 0 }),
  newDraft(ownerId: string): Studio {
    return {
      id: uuid(), owner_id: ownerId, name: "", tagline: "", description: "", photo_urls: [], video_url: null,
      address: { street: "", postal_code: "", city: "", area: "", country: "" }, latitude: 0, longitude: 0,
      contact: { phone: "", email: "", website: "" }, currency: "EUR", price_from: 3000,
      session_types: [{ id: "recording", name: "Recording", details: "", hourly_rate: 3000, minimum_hours: 2, includes_engineer: false }],
      add_ons: [], facilities: [], equipment: [], engineers: [], capacity: 4, genres: [], opening_hours: STANDARD_WEEK,
      rules: [], booking_policy: { instant_book: true, cancellation_policy: "moderate", deposit_percent: 0, minimum_notice_hours: 12, max_advance_days: 90, buffer_minutes: 0, terms: "", accepts_cash: true, check_in_enabled: true },
      status: "draft", is_active: false, rating_average: 0, review_count: 0, booking_count: 0,
    };
  },
};

// MARK: Bookings

export const isActiveStatus = (s: BookingStatus) => s === "pending_approval" || s === "confirmed";
export const isClosedStatus = (s: BookingStatus) => ["declined", "cancelled", "completed", "expired"].includes(s);

export const Bookings = {
  isUpcoming: (b: Booking) => new Date(b.ends_at).getTime() > Date.now() && isActiveStatus(b.status),
  canCancel: (b: Booking) => isActiveStatus(b.status) && new Date(b.starts_at).getTime() > Date.now(),
  canReschedule: (b: Booking) => b.status === "confirmed" && new Date(b.starts_at).getTime() > Date.now(),
  canReview: (b: Booking) => b.status === "completed" && !b.has_review,
  isCash: (b: Booking) => b.payment_method === "cash",
  /** Check-in opens 1 hour before the session and closes when it ends. */
  canCheckIn: (b: Booking) => {
    const now = Date.now();
    return b.status === "confirmed" && !b.artist_checked_in_at && now >= new Date(b.starts_at).getTime() - HOUR && now <= new Date(b.ends_at).getTime();
  },
};

// MARK: Pricing

/** The unit price for `quantity` with volume prices (same as the database's volume_price). */
export function volumePrice(studio: Studio | undefined, target: VolumePrice["target"], targetId: string, quantity: number, fallback: number): number {
  const tier = (studio?.volume_prices ?? [])
    .filter((v) => v.target === target && v.target_id === targetId && v.unit_price > 0 && v.min_qty >= 2 && v.min_qty <= quantity)
    .sort((a, b) => b.min_qty - a.min_qty)[0];
  return tier?.unit_price ?? fallback;
}

/** The volume prices for one session type or add-on, smallest quantity first. */
export const volumeTiers = (studio: Studio, target: VolumePrice["target"], targetId: string) =>
  (studio.volume_prices ?? []).filter((v) => v.target === target && v.target_id === targetId && v.unit_price > 0 && v.min_qty >= 2).sort((a, b) => a.min_qty - b.min_qty);

/** The day rate when this session type is booked per day (same rule as the database). */
export const dayRate = (studio: Studio, sessionTypeId: string): DayRate | undefined =>
  (studio.day_rates ?? []).find((r) => r.session_type_id === sessionTypeId && r.day_price > 0);

/** Hours per day of a day-priced session type (1–12). */
export const hoursPerDay = (rate: DayRate) => Math.min(Math.max(rate.hours_per_day || 8, 1), 12);

export function addOnAmount(addOn: ServiceAddOn, quantity: number, hours: number, studio?: Studio, days = 1): number {
  if (addOn.unit === "per_hour") return volumePrice(studio, "add_on", addOn.id, hours, addOn.price) * hours * days;
  if (addOn.unit === "per_session") return addOn.price * ((studio?.per_day_add_ons ?? []).includes(addOn.id) ? days : 1);
  return volumePrice(studio, "add_on", addOn.id, quantity, addOn.price) * quantity;
}

/** Weekday (1 = Sunday … 7 = Saturday) and minutes after midnight of `date` in `zone`. */
function weekdayAndMinutes(date: Date, zone: string): { weekday: number; minutes: number } {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: zone, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(get("weekday")) + 1;
  return { weekday, minutes: Number(get("hour")) * 60 + Number(get("minute")) };
}

const ruleMatches = (rule: PriceRule, weekday: number, minutes: number) =>
  rule.hourly_rate > 0 && rule.weekdays.includes(weekday) &&
  (rule.from <= rule.to ? minutes >= rule.from && minutes < rule.to : minutes >= rule.from || minutes < rule.to);

/**
 * The session's price with time-based rates (same as the database's session_price): each hour uses the
 * first rule matching when it starts, otherwise the session type's normal rate.
 */
export function sessionPrice(studio: Studio, sessionType: SessionType, hours: number, start?: Date | null): { amount: number; lines: RateLine[] } {
  const rules = (studio.price_rules ?? []).filter((r) => r.session_type_id === sessionType.id);
  const lines: RateLine[] = [];
  let amount = 0;
  for (let i = 0; i < hours; i++) {
    let rule: PriceRule | undefined;
    if (start && rules.length) {
      const { weekday, minutes } = weekdayAndMinutes(new Date(start.getTime() + i * HOUR), studioZone(studio));
      rule = rules.find((r) => ruleMatches(r, weekday, minutes));
    }
    const rate = rule?.hourly_rate ?? volumePrice(studio, "session", sessionType.id, hours, sessionType.hourly_rate);
    const label = rule?.label.trim() || null;
    amount += rate;
    const line = lines.find((l) => l.label === label && l.hourly_rate === rate);
    if (line) { line.hours += 1; line.amount += rate; } else lines.push({ label, hourly_rate: rate, hours: 1, amount: rate });
  }
  return { amount, lines };
}

export function quote(studio: Studio, sessionType: SessionType, hours: number, selected: Record<string, number> = {}, start?: Date | null, days = 1): PriceBreakdown {
  // A day-priced session type: the day's hours are fixed and the price is per day (lower with more days).
  const day = dayRate(studio, sessionType.id);
  const d = day ? Math.max(days, 1) : 1;
  const h = day ? hoursPerDay(day) : Math.max(hours, 1);
  const perDay = day ? volumePrice(studio, "day", sessionType.id, d, day.day_price) : null;
  const timed = day ? { amount: perDay! * d, lines: [] } : sessionPrice(studio, sessionType, h, start);
  const sessionAmount = timed.amount;
  let addOnsAmount = 0;
  for (const addOn of studio.add_ons) {
    const quantity = selected[addOn.id] ?? 0;
    if (quantity > 0) addOnsAmount += addOnAmount(addOn, quantity, h, studio, d);
  }
  const subtotal = sessionAmount + addOnsAmount;
  const serviceFee = Money.percent(subtotal, PlatformConfig.ARTIST_SERVICE_FEE_PERCENT);
  const total = subtotal + serviceFee;
  const depositPercent = Math.min(Math.max(studio.booking_policy.deposit_percent, 0), 100);
  const deposit = depositPercent >= 1 && depositPercent <= 99 ? Money.percent(subtotal, depositPercent) : 0;
  const dueNow = deposit > 0 ? deposit + serviceFee : total;
  const commission = Money.percent(subtotal, PlatformConfig.PLATFORM_FEE_PERCENT);
  return {
    currency: studio.currency, hourly_rate: volumePrice(studio, "session", sessionType.id, h, sessionType.hourly_rate), hours: h, session_amount: sessionAmount, rate_lines: timed.lines, days: d, day_rate: perDay,
    add_ons_amount: addOnsAmount, subtotal, service_fee: serviceFee, total, deposit_amount: deposit, due_now: dueNow,
    due_later: total - dueNow, studio_commission: commission, studio_payout: subtotal - commission,
  };
}

/** Cash is offered when the studio allows it and no card deposit is required. */
export const acceptsCash = (s: Studio) => s.booking_policy.accepts_cash && s.booking_policy.deposit_percent === 0;

export function bookedAddOns(studio: Studio, selected: Record<string, number>, hours: number, days = 1): BookedAddOn[] {
  return studio.add_ons.filter((a) => (selected[a.id] ?? 0) > 0)
    .map((a) => ({ id: a.id, name: a.name, quantity: selected[a.id], amount: addOnAmount(a, selected[a.id], hours, studio, days) }));
}

export function refundPercent(policy: CancellationPolicy, hoursUntilStart: number): number {
  if (policy === "flexible") return hoursUntilStart >= 24 ? 100 : 0;
  if (policy === "moderate") return hoursUntilStart >= 72 ? 100 : hoursUntilStart >= 24 ? 50 : 0;
  return hoursUntilStart >= 24 * 7 ? 50 : 0;
}

export function refundAmount(price: PriceBreakdown, amountPaid: number, policy: CancellationPolicy, startsAt: string, cancelledBy: UserRole): number {
  if (amountPaid <= 0) return 0;
  if (cancelledBy !== "artist") return amountPaid;
  const percent = refundPercent(policy, (new Date(startsAt).getTime() - Date.now()) / HOUR);
  if (percent === 100) return amountPaid;
  return Money.percent(Math.max(amountPaid - price.service_fee, 0), percent);
}

// MARK: Availability

export interface TimeSlot { start: Date; end: Date }
const overlaps = (a: Interval, b: Interval) => a.start < b.end && b.start < a.end;

/** Opening window for `day` (any instant on that date in the studio's time zone), or null when closed. */
export function openingWindow(studio: Studio, day: Date): Interval | null {
  const zone = studioZone(studio);
  const hours = Studios.hours(studio, weekdayOf(day, zone));
  if (!hours || hours.is_closed) return null;
  let closes = hours.closes_at;
  if (closes <= hours.opens_at) closes += 1440;
  const key = dayIn(day, zone);
  return { start: zonedTime(key, hours.opens_at, zone), end: zonedTime(key, closes, zone) };
}

export function availableSlots(studio: Studio, day: Date, hours: number, busy: Interval[], now = new Date(), stepMinutes = 60): TimeSlot[] {
  if (hours <= 0) return [];
  const window = openingWindow(studio, day);
  if (!window) return [];
  const policy = studio.booking_policy;
  const earliest = new Date(now.getTime() + policy.minimum_notice_hours * HOUR);
  const zone = studioZone(studio);
  const latestDay = new Date(zonedTime(dayIn(now, zone), 0, zone).getTime() + (policy.max_advance_days + 1) * DAY);
  if (window.start >= latestDay) return [];
  const buffer = policy.buffer_minutes * 60_000;
  const padded = busy.map((b) => ({ start: new Date(b.start.getTime() - buffer), end: new Date(b.end.getTime() + buffer) }));
  const slots: TimeSlot[] = [];
  for (let start = window.start.getTime(); start + hours * HOUR <= window.end.getTime(); start += stepMinutes * 60_000) {
    const candidate = { start: new Date(start), end: new Date(start + hours * HOUR) };
    if (candidate.start >= earliest && !padded.some((p) => overlaps(p, candidate))) slots.push(candidate);
  }
  return slots;
}

export const isAvailable = (studio: Studio, day: Date, hours: number, busy: Interval[]) => availableSlots(studio, day, hours, busy).length > 0;

/** Next few free start times over the coming days (studio page). */
export function nextSlots(studio: Studio, busy: Interval[], hours: number, limit = 6): TimeSlot[] {
  const result: TimeSlot[] = [];
  for (let i = 0; i < 21 && result.length < limit; i++) result.push(...availableSlots(studio, addDays(new Date(), i), hours, busy));
  return result.slice(0, limit);
}

// MARK: Search

export type StudioSort = "nearest" | "cheapest" | "top_rated" | "most_popular";
export const SORTS: [StudioSort, string][] = [["nearest", "Nearest"], ["cheapest", "Cheapest"], ["top_rated", "Top rated"], ["most_popular", "Most popular"]];

export interface SearchFilters {
  query: string;
  minPrice: number | null;
  maxPrice: number | null;
  maxDistanceKm: number | null;
  genres: Genre[];
  facilities: Facility[];
  equipmentQuery: string;
  equipmentCategories: EquipmentCategory[];
  minRating: number | null;
  availableOn: Date | null;
  sessionHours: number;
  instantBookOnly: boolean;
  offersMixing: boolean;
  offersMastering: boolean;
  engineerIncluded: boolean;
}

export const EMPTY_FILTERS: SearchFilters = {
  query: "", minPrice: null, maxPrice: null, maxDistanceKm: null, genres: [], facilities: [], equipmentQuery: "",
  equipmentCategories: [], minRating: null, availableOn: null, sessionHours: 2, instantBookOnly: false,
  offersMixing: false, offersMastering: false, engineerIncluded: false,
};

export function activeFilterCount(f: SearchFilters): number {
  let n = 0;
  if (f.minPrice != null || f.maxPrice != null) n++;
  if (f.maxDistanceKm != null) n++;
  if (f.genres.length) n++;
  if (f.facilities.length) n++;
  if (f.equipmentQuery || f.equipmentCategories.length) n++;
  if (f.minRating != null) n++;
  if (f.availableOn) n++;
  if (f.instantBookOnly) n++;
  if (f.offersMixing || f.offersMastering || f.engineerIncluded) n++;
  return n;
}

export interface StudioResult { studio: Studio; distance: number | null }

const CITY_ALIASES: Record<string, string> = {
  "københavn": "copenhagen", kobenhavn: "copenhagen", "århus": "aarhus", "athína": "athens", athina: "athens", "αθήνα": "athens",
  "θεσσαλονίκη": "thessaloniki", warszawa: "warsaw", "kraków": "krakow", "wrocław": "wroclaw", "gdańsk": "gdansk", "münchen": "munich",
  "köln": "cologne", wien: "vienna", roma: "rome", milano: "milan", napoli: "naples", firenze: "florence", lisboa: "lisbon",
  praha: "prague", "göteborg": "gothenburg", "den haag": "the hague", bruxelles: "brussels", brussel: "brussels",
};
const SEARCH_LANGS = ["en", "da", "de", "pl", "el", "fr", "es", "it", "sv", "nl"];

export function normalizeText(text: string): string {
  return text.toLowerCase().replace(/ø/g, "o").replace(/æ/g, "ae").replace(/å/g, "a").replace(/ß/g, "ss").replace(/ł/g, "l")
    .normalize("NFD").replace(/\p{Mn}+/gu, "");
}

const countryCache = new Map<string, string[]>();
function countryNames(country: string): string[] {
  const trimmed = country.trim();
  if (!trimmed) return [];
  if (countryCache.has(trimmed)) return countryCache.get(trimmed)!;
  let code: string | null = trimmed.length === 2 ? trimmed.toUpperCase() : null;
  if (!code) {
    const needle = normalizeText(trimmed);
    outer: for (const lang of SEARCH_LANGS) {
      const names = new Intl.DisplayNames([lang], { type: "region" });
      for (let a = 65; a <= 90; a++) for (let b = 65; b <= 90; b++) {
        const candidate = String.fromCharCode(a, b);
        try { if (normalizeText(names.of(candidate) ?? "") === needle) { code = candidate; break outer; } } catch { /* not a region */ }
      }
    }
  }
  const result = code ? [code, ...SEARCH_LANGS.map((l) => { try { return new Intl.DisplayNames([l], { type: "region" }).of(code!) ?? ""; } catch { return ""; } })] : [];
  countryCache.set(trimmed, result);
  return result;
}

function haystack(s: Studio): string {
  const a = s.address;
  return [
    s.name, s.tagline, a.city, a.area, a.street, a.postal_code, a.country, s.description, ...countryNames(a.country),
    CITY_ALIASES[a.city.toLowerCase()] ?? "", ...s.genres.map(genreTitle), ...(s.admin_tags ?? []), ...s.equipment.map((e) => e.name),
  ].join(" ");
}

export function searchStudios(studios: Studio[], f: SearchFilters, sort: StudioSort, origin: GeoPoint | null, busy: Record<string, Interval[]> = {}): StudioResult[] {
  const words = normalizeText(f.query.trim()).split(" ").filter(Boolean);
  const gear = f.equipmentQuery.trim().toLowerCase();
  const results: StudioResult[] = [];
  for (const s of studios) {
    if (!Studios.isBookable(s)) continue;
    const distance = origin && (s.latitude || s.longitude) ? distanceMeters(origin, s) : null;
    if (words.length) {
      const text = normalizeText(haystack(s) + " " + s.genres.map((g) => t(genreTitle(g))).join(" "));
      if (!words.every((w) => text.includes(w))) continue;
    }
    if (f.minPrice != null && s.price_from < f.minPrice) continue;
    if (f.maxPrice != null && s.price_from > f.maxPrice) continue;
    if (f.maxDistanceKm != null && distance != null && distance > f.maxDistanceKm * 1000) continue;
    if (f.genres.length && !f.genres.some((g) => s.genres.includes(g))) continue;
    if (!f.facilities.every((x) => s.facilities.includes(x))) continue;
    if (!f.equipmentCategories.every((c) => s.equipment.some((e) => e.category === c))) continue;
    if (gear && !s.equipment.some((e) => e.name.toLowerCase().includes(gear))) continue;
    if (f.minRating != null && s.rating_average < f.minRating) continue;
    if (f.instantBookOnly && !s.booking_policy.instant_book) continue;
    if (f.offersMixing && !Studios.offersMixing(s)) continue;
    if (f.offersMastering && !Studios.offersMastering(s)) continue;
    if (f.engineerIncluded && !s.session_types.some((x) => x.includes_engineer) && !s.add_ons.some((a) => a.kind === "engineer")) continue;
    if (f.availableOn && !isAvailable(s, f.availableOn, f.sessionHours, busy[s.id] ?? [])) continue;
    results.push({ studio: s, distance });
  }
  const sorted = [...results].sort((a, b) => {
    if (sort === "nearest") return (a.distance ?? Infinity) - (b.distance ?? Infinity);
    if (sort === "cheapest") return a.studio.price_from - b.studio.price_from;
    if (sort === "top_rated") return b.studio.rating_average - a.studio.rating_average || b.studio.review_count - a.studio.review_count;
    return b.studio.booking_count - a.studio.booking_count;
  });
  // Promoted studios first; the chosen sort applies within each group.
  return [...sorted.filter((r) => Studios.isPromoted(r.studio)), ...sorted.filter((r) => !Studios.isPromoted(r.studio))];
}

// MARK: Validation

export function studioProblems(s: Studio): string[] {
  const problems: string[] = [];
  if (s.name.trim().length < 3) problems.push("Add your studio's name.");
  if (s.description.length < 40) problems.push("Write a description of at least 40 characters.");
  if (!s.photo_urls.length) problems.push("Add at least one photo.");
  if (!s.address.street || !s.address.city) problems.push("Add the studio's address.");
  if (s.latitude === 0 && s.longitude === 0) problems.push("Place your studio on the map.");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s.contact.email.trim())) problems.push("Add a valid email address.");
  if ((s.contact.phone.match(/\d/g) ?? []).length < 6) problems.push("Add a phone number.");
  if (!s.session_types.length || s.session_types.some((x) => x.hourly_rate <= 0)) problems.push("Set a price for each session type.");
  if (s.opening_hours.every((h) => h.is_closed)) problems.push("Set your opening hours.");
  if (!s.genres.length) problems.push("Pick at least one genre.");
  return problems;
}

export const PASSWORD_MIN = 10;
export function passwordProblem(password: string): string | null {
  const ok = password.length >= PASSWORD_MIN && /[A-ZÆØÅ]/.test(password) && /[a-zæøå]/.test(password) && /\d/.test(password);
  return ok ? null : format("At least %lld characters with upper- and lowercase letters and a number.", PASSWORD_MIN);
}

/** 0–4 for the strength meter on sign-up (same scoring as the apps). */
export function passwordStrength(password: string): number {
  let points = 0;
  if (password.length >= PASSWORD_MIN) points++;
  if (password.length >= 14) points++;
  if (/\d/.test(password) && /\p{L}/u.test(password)) points++;
  if (/\p{Lu}/u.test(password) && /[^\p{L}\d]/u.test(password)) points++;
  return passwordProblem(password) == null ? Math.max(points, 1) : Math.min(points, 1);
}

// MARK: Earnings

export interface EarningsSummary {
  grossThisMonth: number; netThisMonth: number; netAllTime: number; pendingPayout: number;
  completedSessions: number; upcomingSessions: number; hoursBooked: number; monthly: { month: Date; amount: number }[];
}

export function earningsSummary(bookings: Booking[], payouts: Payout[]): EarningsSummary {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const completed = bookings.filter((b) => b.status === "completed");
  const inMonth = completed.filter((b) => new Date(b.ends_at) >= monthStart);
  const monthly = [5, 4, 3, 2, 1, 0].map((offset) => {
    const start = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const end = new Date(now.getFullYear(), now.getMonth() - offset + 1, 1);
    return { month: start, amount: completed.filter((b) => new Date(b.ends_at) >= start && new Date(b.ends_at) < end).reduce((n, b) => n + b.price.studio_payout, 0) };
  });
  return {
    grossThisMonth: inMonth.reduce((n, b) => n + b.price.subtotal, 0),
    netThisMonth: inMonth.reduce((n, b) => n + b.price.studio_payout, 0),
    netAllTime: completed.reduce((n, b) => n + b.price.studio_payout, 0),
    pendingPayout: payouts.filter((p) => p.status === "scheduled" || p.status === "in_transit").reduce((n, p) => n + p.amount, 0),
    completedSessions: completed.length,
    upcomingSessions: bookings.filter(Bookings.isUpcoming).length,
    hoursBooked: completed.reduce((n, b) => n + b.hours, 0),
    monthly,
  };
}

// MARK: Social links

/** A tappable address, also when people typed just a username ("name", "@name") or a site without "https://". */
export function resolveLink(link: SocialLink): string | null {
  const text = link.url.trim();
  if (!text) return null;
  if (/^https?:\/\//i.test(text)) return text;
  if (text.includes(".") && !text.startsWith("@") && !text.includes(" ")) return `https://${text}`;
  const handle = encodeURIComponent(text.replace(/^[@/ ]+|[@/ ]+$/g, ""));
  switch (link.platform) {
    case "instagram": return `https://www.instagram.com/${handle}`;
    case "tiktok": return `https://www.tiktok.com/@${handle}`;
    case "youtube": return `https://www.youtube.com/@${handle}`;
    case "soundcloud": return `https://soundcloud.com/${handle}`;
    case "spotify": return `https://open.spotify.com/search/${handle}`;
    case "apple_music": return `https://music.apple.com/search?term=${handle}`;
    default: return `https://${handle}`;
  }
}

export function greeting(): string {
  const h = new Date().getHours();
  return h >= 5 && h < 12 ? "Good morning" : h >= 12 && h < 18 ? "Good afternoon" : "Good evening";
}
