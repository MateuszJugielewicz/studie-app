import type { AdminApi, StudioDecision } from "./api";
import type {
  FeeBalance, FeeInvoice, MfaState,
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, StudioStatus, Transaction,
} from "./types";

const DAY = 86_400_000;
const iso = (offsetDays: number, hour = 12) => {
  const d = new Date(Date.now() + offsetDays * DAY);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
};
let seq = 1;
const id = () => `00000000-0000-4000-8000-${String(seq++).padStart(12, "0")}`;
const pct = (amount: number, p: number) => Math.floor((amount * p + 50) / 100);

function makeStudio(name: string, area: string, city: string, rate: number, status: StudioStatus, owner: string, extra: Partial<Studio> = {}): Studio {
  const slug = name.toLowerCase().replace(/\s+/g, "-");
  return {
    id: id(),
    owner_id: owner,
    name,
    tagline: `Professional recording in ${area}`,
    description: `${name} is a recording space in ${area}, ${city}. Treated rooms, great monitoring and a friendly team.`,
    photo_urls: [1, 2, 3].map((n) => `https://picsum.photos/seed/${slug}-${n}/800/500`),
    video_url: null,
    address: { street: "Example street 12", postal_code: "106 81", city, area, country: city === "Copenhagen" ? "Denmark" : "Greece" },
    latitude: 37.98,
    longitude: 23.72,
    contact: { phone: "+30 210 000 0000", email: `hello@${slug}.com`, website: `https://${slug}.com` },
    currency: city === "Copenhagen" ? "DKK" : "EUR",
    price_from: rate,
    session_types: [
      { id: "recording", name: "Recording", details: "", hourly_rate: rate, minimum_hours: 2, includes_engineer: false },
      { id: "recording_engineer", name: "Recording + engineer", details: "", hourly_rate: Math.round(rate * 1.5), minimum_hours: 2, includes_engineer: true },
    ],
    add_ons: [{ id: "mixing", kind: "mixing", name: "Mixing", price: rate * 3, unit: "per_track" }],
    facilities: ["vocal_booth", "control_room", "wifi", "air_conditioning"],
    equipment: [
      { id: "m1", category: "microphone", name: "Neumann U87 Ai" },
      { id: "m2", category: "microphone", name: "Shure SM7B" },
      { id: "g1", category: "interface", name: "UA Apollo x8" },
    ],
    engineers: [{ id: "e1", name: "Dimitris P.", role: "Engineer", bio: "" }],
    capacity: 5,
    genres: ["hip_hop", "pop", "rnb"],
    opening_hours: [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, is_closed: weekday === 1, opens_at: 600, closes_at: 1320 })),
    rules: ["No smoking", "No food in the control room"],
    booking_policy: { instant_book: true, cancellation_policy: "moderate", deposit_percent: 0 },
    status,
    is_active: status === "approved",
    is_verified: status === "approved",
    admin_note: null,
    rating_average: status === "approved" ? 4.2 + Math.round(Math.random() * 8) / 10 : 0,
    review_count: status === "approved" ? 5 + Math.floor(Math.random() * 40) : 0,
    booking_count: 0,
    created_at: iso(-60),
    submitted_at: iso(-2),
    ...extra,
  };
}

class DemoStore {
  users: AdminUser[] = [];
  studios: Studio[] = [];
  events: StudioEvent[] = [];
  bookings: Booking[] = [];
  transactions: Transaction[] = [];
  payouts: Payout[] = [];
  disputes: Dispute[] = [];
  reports: Report[] = [];
  reviews: Review[] = [];
  ledger: { studio_id: string; currency: string; amount: number; kind: string; created_at: string }[] = [];
  invoices: FeeInvoice[] = [];

  constructor() {
    const artistNames = ["Nova Lykke", "Kostas K", "The Salt Flats", "MIRA", "Elena V", "Blue Harbour", "Yannis B", "Sofie Dahl"];
    const artists: AdminUser[] = artistNames.map((name, i) => ({
      id: id(), email: `${name.toLowerCase().replace(/\s+/g, ".")}@mail.com`, role: "artist", status: i === 6 ? "suspended" : "active",
      status_reason: i === 6 ? "Repeated no-shows" : null, is_verified: i % 3 === 0, created_at: iso(-100 + i * 9),
      artist_name: name, artist_city: i > 5 ? "Copenhagen" : "Athens", studio_id: null, studio_name: null, booking_count: 0,
    }));
    const owners: AdminUser[] = ["Exarchia Sound Lab", "Psyri Records", "Koukaki Live Rooms", "Gazi Beat Factory", "Pangrati Mix Suite", "Nørrebro Tapehouse", "Kolonaki Vocal Room", "Piraeus Harbour Studio", "Marousi Beat Loft"].map((name, i) => ({
      id: id(), email: `owner${i + 1}@studios.com`, role: "studio_owner", status: "active", status_reason: null, is_verified: i < 5,
      created_at: iso(-200 + i * 15), artist_name: null, artist_city: null, studio_id: null, studio_name: name, booking_count: 0,
    }));
    this.users = [...artists, ...owners];

    const specs: [string, string, string, number, StudioStatus][] = [
      ["Exarchia Sound Lab", "Exarchia", "Athens", 2500, "approved"],
      ["Psyri Records", "Psyri", "Athens", 1500, "approved"],
      ["Koukaki Live Rooms", "Koukaki", "Athens", 4500, "approved"],
      ["Gazi Beat Factory", "Gazi", "Athens", 3000, "approved"],
      ["Pangrati Mix Suite", "Pangrati", "Athens", 5500, "approved"],
      ["Nørrebro Tapehouse", "Nørrebro", "Copenhagen", 45000, "approved"],
      ["Kolonaki Vocal Room", "Kolonaki", "Athens", 3500, "pending_review"],
      ["Piraeus Harbour Studio", "Piraeus", "Piraeus", 3200, "pending_review"],
      ["Marousi Beat Loft", "Marousi", "Athens", 2000, "changes_requested"],
    ];
    this.studios = specs.map(([name, area, city, rate, status], i) => {
      const studio = makeStudio(name, area, city, rate, status, owners[i].id, status === "changes_requested" ? { admin_note: "Please add photos of the vocal booth." } : {});
      owners[i].studio_id = studio.id;
      this.events.push({ id: id(), studio_id: studio.id, from_status: "draft", to_status: "pending_review", note: null, created_at: studio.submitted_at! });
      if (status !== "pending_review") {
        this.events.push({ id: id(), studio_id: studio.id, from_status: "pending_review", to_status: status, note: studio.admin_note, created_at: iso(-1) });
      }
      return studio;
    });

    const live = this.studios.filter((s) => s.status === "approved");
    const statuses: BookingStatus[] = ["completed", "completed", "completed", "confirmed", "confirmed", "cancelled", "pending_approval", "completed", "declined", "disputed"];
    for (let i = 0; i < 60; i++) {
      const studio = live[i % live.length];
      const artist = artists[(i * 3) % artists.length];
      const status = statuses[i % statuses.length];
      const dayOffset = status === "completed" || status === "disputed" ? -1 - (i % 28) : status === "cancelled" || status === "declined" ? (i % 10) - 5 : 1 + (i % 14);
      const hours = 2 + (i % 4);
      const subtotal = studio.price_from * hours;
      const fee = 0; // no artist fee – Sonora takes 10% from the studio
      const commission = pct(subtotal, 10);
      const cash = i % 4 === 1 && status !== "pending_approval";
      const refund = status === "cancelled" ? subtotal + fee : status === "declined" ? subtotal + fee : 0;
      const booking: Booking = {
        id: id(), reference: `SON-${(100000 + i * 7919).toString(36).toUpperCase().slice(-6)}`, artist_id: artist.id, studio_id: studio.id,
        artist_name: artist.artist_name!, studio_name: studio.name, session_type_name: "Recording",
        starts_at: iso(dayOffset, 10 + (i % 8)), ends_at: iso(dayOffset, 10 + (i % 8) + hours), hours, status,
        payment_status: cash ? (status === "completed" ? "paid" : status === "confirmed" ? "pay_at_studio" : "unpaid")
          : status === "pending_approval" ? "authorized" : status === "cancelled" || status === "declined" ? "refunded" : "paid",
        payment_method: cash ? "cash" : i % 3 === 0 ? "card" : "apple_pay",
        price: { currency: studio.currency, subtotal, service_fee: fee, total: subtotal + fee, due_now: subtotal + fee, due_later: 0, studio_commission: commission, studio_payout: subtotal - commission },
        notes: "", cancellation_reason: status === "cancelled" ? "Change of plans" : null, cancelled_by: status === "cancelled" ? "artist" : null,
        refund_amount: cash ? 0 : refund, created_at: iso(dayOffset - 5 - (i % 3)),
      };
      this.bookings.push(booking);
      studio.booking_count++;
      artist.booking_count++;
      if (cash) {
        if (status === "completed") {
          this.ledger.push({ studio_id: studio.id, currency: studio.currency, amount: commission, kind: "cash_commission", created_at: booking.ends_at });
        }
        continue;
      }
      if (status !== "pending_approval" && status !== "declined") {
        this.transactions.push({
          id: id(), booking_id: booking.id, studio_id: studio.id, artist_id: artist.id, kind: "charge", method: i % 3 === 0 ? "card" : "apple_pay",
          status: "succeeded", amount: subtotal + fee, platform_fee: fee + commission, currency: studio.currency, receipt_number: `RCPT-${1000 + i}`,
          failure_reason: null, provider_reference: `pi_demo_${i}`, created_at: booking.created_at,
        });
      }
      if (refund > 0 && status === "cancelled") {
        this.transactions.push({
          id: id(), booking_id: booking.id, studio_id: studio.id, artist_id: artist.id, kind: "refund", method: "card",
          status: "succeeded", amount: refund, platform_fee: 0, currency: studio.currency, receipt_number: `RCPT-R${1000 + i}`,
          failure_reason: null, provider_reference: `re_demo_${i}`, created_at: iso(dayOffset - 2),
        });
      }
      if (status === "completed") {
        const scheduled = new Date(new Date(booking.ends_at).getTime() + 2 * DAY);
        this.payouts.push({
          id: id(), studio_id: studio.id, amount: subtotal - commission, currency: studio.currency,
          status: scheduled.getTime() < Date.now() ? "paid" : "scheduled", scheduled_for: scheduled.toISOString(),
          paid_at: scheduled.getTime() < Date.now() ? scheduled.toISOString() : null, booking_ids: [booking.id], failure_reason: null,
        });
      }
      if (status === "disputed") {
        this.disputes.push({ id: id(), booking_id: booking.id, opened_by: artist.id, reason: "The studio was double-booked and we only got 1 hour.", status: "open", resolution: null, created_at: iso(-1) });
      }
    }
    for (let i = 0; i < 3; i++) {
      const b = this.bookings[i * 5];
      this.transactions.push({
        id: id(), booking_id: b.id, studio_id: b.studio_id, artist_id: b.artist_id, kind: "charge", method: "card", status: "failed",
        amount: b.price.total, platform_fee: 0, currency: b.price.currency, receipt_number: `RCPT-F${i}`,
        failure_reason: ["Your card was declined.", "Insufficient funds.", "Authentication required."][i], provider_reference: `pi_fail_${i}`, created_at: iso(-i - 1),
      });
    }

    for (const b of this.bookings.filter((x) => x.status === "completed").slice(0, 18)) {
      this.reviews.push({
        id: id(), booking_id: b.id, studio_id: b.studio_id, artist_id: b.artist_id, artist_name: b.artist_name,
        rating: 3 + (b.hours % 3), text: "Great sound and a friendly engineer. Will book again!", studio_reply: null, is_hidden: false, created_at: b.ends_at,
      });
    }
    const fakeReview: Review = { id: id(), booking_id: this.bookings[1].id, studio_id: live[1].id, artist_id: artists[4].id, artist_name: "Elena V", rating: 1, text: "Worst place ever!!! Go to my cousin's studio instead: www.example-spam.com", studio_reply: null, is_hidden: false, created_at: iso(-3) };
    this.reviews.push(fakeReview);

    this.reports = [
      { id: id(), reporter_id: owners[1].id, target_type: "review", target_id: fakeReview.id, reason: "fake", details: "This person never booked with us.", status: "open", admin_note: null, created_at: iso(-2) },
      { id: id(), reporter_id: artists[0].id, target_type: "message", target_id: id(), reason: "spam", details: "Asked me to pay outside the app.", status: "open", admin_note: null, created_at: iso(-1) },
      { id: id(), reporter_id: artists[2].id, target_type: "studio", target_id: live[3].id, reason: "inappropriate", details: "Photos don't match the actual studio.", status: "open", admin_note: null, created_at: iso(-4) },
      { id: id(), reporter_id: owners[0].id, target_type: "user", target_id: artists[6].id, reason: "no_show", details: "Didn't show up twice.", status: "resolved", admin_note: "User suspended.", created_at: iso(-10) },
    ];
  }
}

const wait = () => new Promise((r) => setTimeout(r, 150));

export class DemoAdminApi implements AdminApi {
  readonly isDemo = true;
  private db = new DemoStore();
  private signedIn = false;

  async signIn() {
    await wait();
    this.signedIn = true;
  }
  async signOut() {
    this.signedIn = false;
  }
  async currentAdminEmail() {
    return this.signedIn ? "admin@sonora.app" : null;
  }
  async mfaState(): Promise<MfaState> {
    return { kind: "verified" }; // demo mode has no second factor
  }
  async verifyMfa() {}

  async feeBalances(): Promise<FeeBalance[]> {
    await wait();
    const map = new Map<string, FeeBalance>();
    for (const l of this.db.ledger) {
      const key = `${l.studio_id}|${l.currency}`;
      const studio = this.db.studios.find((s) => s.id === l.studio_id)!;
      const row = map.get(key) ?? { studio_id: l.studio_id, studio_name: studio.name, currency: l.currency, balance: 0, last_commission_at: null };
      row.balance += l.amount;
      if (l.kind === "cash_commission" && (!row.last_commission_at || l.created_at > row.last_commission_at)) row.last_commission_at = l.created_at;
      map.set(key, row);
    }
    return [...map.values()].sort((a, b) => b.balance - a.balance);
  }
  async feeInvoices() {
    return structuredClone(this.db.invoices);
  }
  async recordFeeSettlement(studioId: string, amount: number, currency: string, kind: "manual_payment" | "waiver") {
    if (amount <= 0) throw new Error("Amount must be positive.");
    this.db.ledger.push({ studio_id: studioId, currency, amount: -amount, kind, created_at: new Date().toISOString() });
  }
  async sendFeeInvoice(studioId: string, currency: string) {
    const owed = this.db.ledger.filter((l) => l.studio_id === studioId && l.currency === currency).reduce((s, l) => s + l.amount, 0)
      - this.db.invoices.filter((i) => i.studio_id === studioId && i.currency === currency && i.status === "open").reduce((s, i) => s + i.amount, 0);
    if (owed <= 0) throw new Error("Nothing to invoice – open invoices already cover the balance.");
    this.db.invoices.push({ id: id(), studio_id: studioId, amount: owed, currency, status: "open", hosted_invoice_url: null, created_at: new Date().toISOString(), paid_at: null });
  }

  async stats(days: number): Promise<DashboardStats> {
    await wait();
    const from = Date.now() - days * DAY;
    const inRange = this.db.bookings.filter((b) => new Date(b.created_at).getTime() >= from);
    const ok = inRange.filter((b) => ["confirmed", "completed", "disputed"].includes(b.status));
    const revenue: DashboardStats["revenue"] = {};
    const bucket = (currency: string) => (revenue[currency] ??= { gross: 0, card: 0, cash: 0, platform: 0, refunds: 0, fees_owed: 0 });
    for (const b of this.db.bookings.filter((b) => b.status === "completed" && new Date(b.ends_at).getTime() >= from)) {
      const r = bucket(b.price.currency);
      if (b.payment_method === "cash") r.cash += b.price.total;
      else r.card += b.price.total;
      r.gross += b.price.total;
      r.platform += b.price.studio_commission + b.price.service_fee;
    }
    for (const t of this.db.transactions.filter((t) => t.kind === "refund" && t.status === "succeeded" && new Date(t.created_at).getTime() >= from)) {
      bucket(t.currency).refunds += t.amount;
    }
    for (const l of this.db.ledger) bucket(l.currency).fees_owed += l.amount;
    const byStudio = new Map<string, number>();
    const byArea = new Map<string, number>();
    for (const b of ok) {
      byStudio.set(b.studio_id, (byStudio.get(b.studio_id) ?? 0) + 1);
      const s = this.db.studios.find((x) => x.id === b.studio_id)!;
      const key = `${s.address.city}|${s.address.area}`;
      byArea.set(key, (byArea.get(key) ?? 0) + 1);
    }
    const perDay = new Map<string, number>();
    for (const b of inRange) {
      const day = b.created_at.slice(0, 10);
      perDay.set(day, (perDay.get(day) ?? 0) + 1);
    }
    return {
      artists: this.db.users.filter((u) => u.role === "artist").length,
      studio_owners: this.db.users.filter((u) => u.role === "studio_owner").length,
      studios_live: this.db.studios.filter((s) => s.status === "approved" && s.is_active).length,
      studios_pending: this.db.studios.filter((s) => s.status === "pending_review").length,
      bookings_total: inRange.length,
      bookings_confirmed: inRange.filter((b) => ["confirmed", "completed"].includes(b.status)).length,
      bookings_cancelled: inRange.filter((b) => ["cancelled", "declined"].includes(b.status)).length,
      booking_rate: inRange.length ? Math.round((1000 * ok.length) / inRange.length) / 10 : 0,
      open_reports: this.db.reports.filter((r) => r.status === "open").length,
      open_disputes: this.db.disputes.filter((d) => d.status === "open").length,
      failed_payments: this.db.transactions.filter((t) => t.status === "failed").length,
      revenue,
      top_studios: [...byStudio.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([sid, n]) => {
        const s = this.db.studios.find((x) => x.id === sid)!;
        return { id: sid, name: s.name, city: s.address.city, bookings: n, rating: s.rating_average };
      }),
      top_areas: [...byArea.entries()].sort((a, b) => b[1] - a[1]).map(([key, n]) => {
        const [city, area] = key.split("|");
        return { city, area, bookings: n };
      }),
      bookings_per_day: [...perDay.entries()].sort().map(([day, bookings]) => ({ day, bookings })),
    };
  }

  async users() {
    await wait();
    return structuredClone(this.db.users);
  }
  async setUserStatus(userId: string, status: AccountStatus, reason?: string) {
    const user = this.db.users.find((u) => u.id === userId)!;
    user.status = status;
    user.status_reason = reason ?? null;
    if (status !== "active") this.db.studios.filter((s) => s.owner_id === userId).forEach((s) => (s.is_active = false));
  }
  async verifyUser(userId: string, verified: boolean) {
    this.db.users.find((u) => u.id === userId)!.is_verified = verified;
  }

  async studios() {
    await wait();
    return structuredClone(this.db.studios);
  }
  async studioEvents(studioId: string) {
    return this.db.events.filter((e) => e.studio_id === studioId).sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  async reviewStudio(studioId: string, decision: StudioDecision, note?: string) {
    if (decision !== "approve" && !note?.trim()) throw new Error("Add a note explaining what the studio should change.");
    const s = this.db.studios.find((x) => x.id === studioId)!;
    const to: StudioStatus = decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "changes_requested";
    this.db.events.push({ id: id(), studio_id: studioId, from_status: s.status, to_status: to, note: note ?? null, created_at: new Date().toISOString() });
    s.status = to;
    s.is_active = to === "approved";
    if (to === "approved") s.is_verified = true;
    s.admin_note = note ?? null;
  }
  async setStudioState(studioId: string, patch: { active?: boolean; verified?: boolean; suspended?: boolean; note?: string }) {
    const s = this.db.studios.find((x) => x.id === studioId)!;
    if (patch.suspended === true) {
      this.db.events.push({ id: id(), studio_id: studioId, from_status: s.status, to_status: "suspended", note: patch.note ?? null, created_at: new Date().toISOString() });
      s.status = "suspended";
      s.is_active = false;
    }
    if (patch.suspended === false && s.status === "suspended") s.status = "approved";
    if (patch.active !== undefined) s.is_active = patch.active && s.status === "approved";
    if (patch.verified !== undefined) s.is_verified = patch.verified;
  }
  async updateStudio(studioId: string, patch: Partial<Pick<Studio, "name" | "tagline" | "description" | "capacity" | "rules">>) {
    Object.assign(this.db.studios.find((x) => x.id === studioId)!, patch);
  }

  async bookings() {
    await wait();
    return structuredClone(this.db.bookings).sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  async disputes() {
    return structuredClone(this.db.disputes);
  }
  async refund(bookingId: string, amount: number | undefined, reason: string) {
    const b = this.db.bookings.find((x) => x.id === bookingId)!;
    const paid = this.db.transactions.filter((t) => t.booking_id === bookingId && t.status === "succeeded").reduce((s, t) => s + (t.kind === "refund" ? -t.amount : t.amount), 0);
    const value = amount ?? paid;
    if (value <= 0 || value > paid) throw new Error(`At most ${paid} can be refunded.`);
    this.db.transactions.push({
      id: id(), booking_id: b.id, studio_id: b.studio_id, artist_id: b.artist_id, kind: "refund", method: "card", status: "succeeded",
      amount: value, platform_fee: 0, currency: b.price.currency, receipt_number: `RCPT-A${seq}`, failure_reason: reason, provider_reference: null, created_at: new Date().toISOString(),
    });
    b.refund_amount += value;
    b.payment_status = value >= paid ? "refunded" : "partially_refunded";
  }
  async resolveDispute(disputeId: string, resolution: string, bookingStatus: BookingStatus) {
    const d = this.db.disputes.find((x) => x.id === disputeId)!;
    d.status = "resolved";
    d.resolution = resolution;
    const b = this.db.bookings.find((x) => x.id === d.booking_id)!;
    if (b.status === "disputed") b.status = bookingStatus;
  }

  async transactions() {
    await wait();
    return structuredClone(this.db.transactions).sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  async payouts() {
    return structuredClone(this.db.payouts).sort((a, b) => b.scheduled_for.localeCompare(a.scheduled_for));
  }

  async reports() {
    await wait();
    return structuredClone(this.db.reports);
  }
  async reportTarget(report: Report): Promise<ReportTargetDetails> {
    switch (report.target_type) {
      case "user": {
        const u = this.db.users.find((x) => x.id === report.target_id);
        return { title: u ? `${u.artist_name ?? u.studio_name} (${u.role})` : "Unknown user", userId: report.target_id };
      }
      case "studio": {
        const s = this.db.studios.find((x) => x.id === report.target_id);
        return { title: s?.name ?? "Unknown studio", studioId: report.target_id, userId: s?.owner_id };
      }
      case "review": {
        const r = this.db.reviews.find((x) => x.id === report.target_id);
        return { title: r ? `${r.rating}★ review by ${r.artist_name}` : "Unknown review", body: r?.text, reviewId: report.target_id, userId: r?.artist_id };
      }
      case "message":
        return { title: "Chat message", body: "Hey, pay me directly on Revolut and I'll give you 20% off 😉", userId: this.db.users[9].id };
      case "booking":
        return { title: "Booking" };
    }
  }
  async resolveReport(reportId: string, status: ReportStatus, note?: string) {
    const r = this.db.reports.find((x) => x.id === reportId)!;
    r.status = status;
    r.admin_note = note ?? null;
  }
  async reviews() {
    return structuredClone(this.db.reviews);
  }
  async setReviewHidden(reviewId: string, hidden: boolean) {
    this.db.reviews.find((x) => x.id === reviewId)!.is_hidden = hidden;
  }
}
