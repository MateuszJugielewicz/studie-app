// Row shapes returned by Supabase (snake_case). Mirrors supabase/migrations.

export type UserRole = "artist" | "studio_owner" | "admin";
export type AccountStatus = "active" | "suspended" | "banned";
export type StudioStatus = "draft" | "pending_review" | "changes_requested" | "approved" | "rejected" | "suspended";
export type BookingStatus =
  | "awaiting_payment" | "pending_approval" | "confirmed" | "declined" | "cancelled" | "completed" | "disputed" | "expired";
export type PaymentStatus = "unpaid" | "authorized" | "deposit_paid" | "paid" | "partially_refunded" | "refunded" | "failed" | "pay_at_studio";
export type ReportStatus = "open" | "resolved" | "dismissed";
export type ReportTarget = "user" | "studio" | "review" | "message" | "booking";

export interface AdminUser {
  id: string;
  email: string;
  role: UserRole;
  status: AccountStatus;
  status_reason: string | null;
  is_verified: boolean;
  created_at: string;
  artist_name: string | null;
  artist_city: string | null;
  studio_id: string | null;
  studio_name: string | null;
  booking_count: number;
}

export interface SessionType { id: string; name: string; details: string; hourly_rate: number; minimum_hours: number; includes_engineer: boolean }
export interface ServiceAddOn { id: string; kind: string; name: string; price: number; unit: string }
export interface EquipmentItem { id: string; category: string; name: string }
export interface OpeningHours { weekday: number; is_closed: boolean; opens_at: number; closes_at: number }

export interface Studio {
  id: string;
  owner_id: string;
  name: string;
  tagline: string;
  description: string;
  photo_urls: string[];
  video_url: string | null;
  address: { street: string; postal_code: string; city: string; area: string; country: string };
  latitude: number;
  longitude: number;
  contact: { phone: string; email: string; website: string };
  currency: string;
  price_from: number;
  session_types: SessionType[];
  add_ons: ServiceAddOn[];
  facilities: string[];
  equipment: EquipmentItem[];
  engineers: { id: string; name: string; role: string; bio: string }[];
  capacity: number;
  genres: string[];
  opening_hours: OpeningHours[];
  rules: string[];
  booking_policy: { instant_book?: boolean; cancellation_policy?: string; deposit_percent?: number; terms?: string };
  status: StudioStatus;
  is_active: boolean;
  is_verified: boolean;
  admin_note: string | null;
  rating_average: number;
  review_count: number;
  booking_count: number;
  created_at: string;
  submitted_at: string | null;
}

export interface StudioEvent { id: string; studio_id: string; from_status: StudioStatus | null; to_status: StudioStatus; note: string | null; created_at: string }

export interface PriceBreakdown {
  currency: string;
  subtotal: number;
  service_fee: number;
  total: number;
  due_now: number;
  due_later: number;
  studio_commission: number;
  studio_payout: number;
}

export interface Booking {
  id: string;
  reference: string;
  artist_id: string;
  studio_id: string;
  artist_name: string;
  studio_name: string;
  session_type_name: string;
  starts_at: string;
  ends_at: string;
  hours: number;
  status: BookingStatus;
  payment_status: PaymentStatus;
  price: PriceBreakdown;
  notes: string;
  cancellation_reason: string | null;
  cancelled_by: UserRole | null;
  refund_amount: number;
  payment_method: "card" | "apple_pay" | "google_pay" | "cash" | null;
  created_at: string;
}

export interface FeeBalance {
  studio_id: string;
  studio_name: string;
  currency: string;
  balance: number;
  last_commission_at: string | null;
}

export interface FeeInvoice {
  id: string;
  studio_id: string;
  amount: number;
  currency: string;
  status: "open" | "paid" | "void";
  hosted_invoice_url: string | null;
  created_at: string;
  paid_at: string | null;
}

export type MfaState =
  | { kind: "verified" }
  | { kind: "verify"; factorId: string }
  | { kind: "enroll"; factorId: string; qrCode: string; secret: string };

export interface Transaction {
  id: string;
  booking_id: string;
  studio_id: string;
  artist_id: string;
  kind: "charge" | "balance" | "refund";
  method: "card" | "apple_pay" | "google_pay" | "cash";
  status: "pending" | "succeeded" | "failed";
  amount: number;
  platform_fee: number;
  currency: string;
  receipt_number: string;
  failure_reason: string | null;
  provider_reference: string | null;
  created_at: string;
}

export interface Payout {
  id: string;
  studio_id: string;
  amount: number;
  currency: string;
  status: "scheduled" | "in_transit" | "paid" | "failed";
  scheduled_for: string;
  paid_at: string | null;
  booking_ids: string[];
  failure_reason: string | null;
}

export interface Dispute {
  id: string;
  booking_id: string;
  opened_by: string;
  reason: string;
  status: ReportStatus;
  resolution: string | null;
  created_at: string;
}

export interface Report {
  id: string;
  reporter_id: string;
  target_type: ReportTarget;
  target_id: string;
  reason: string;
  details: string;
  status: ReportStatus;
  admin_note: string | null;
  created_at: string;
}

export interface Review {
  id: string;
  booking_id: string;
  studio_id: string;
  artist_id: string;
  artist_name: string;
  rating: number;
  text: string;
  studio_reply: string | null;
  is_hidden: boolean;
  created_at: string;
}

export interface Message {
  id: string;
  conversation_id: string;
  sender_id: string | null;
  kind: string;
  body: string;
  created_at: string;
}

export interface DashboardStats {
  artists: number;
  studio_owners: number;
  studios_live: number;
  studios_pending: number;
  bookings_total: number;
  bookings_confirmed: number;
  bookings_cancelled: number;
  booking_rate: number;
  open_reports: number;
  open_disputes: number;
  failed_payments: number;
  revenue: Record<string, { gross: number; card: number; cash: number; platform: number; refunds: number; fees_owed: number }>;
  top_studios: { id: string; name: string; city: string; bookings: number; rating: number }[];
  top_areas: { city: string; area: string | null; bookings: number }[];
  bookings_per_day: { day: string; bookings: number }[];
}

/** What a report points at, resolved for display. */
export interface ReportTargetDetails {
  title: string;
  body?: string;
  userId?: string;
  studioId?: string;
  reviewId?: string;
}
