// Row shapes (snake_case, as stored in Postgres). Only fields used by the functions are listed.

export type UserRole = "artist" | "studio_owner" | "admin";
export type BookingStatus =
  | "awaiting_payment" | "pending_approval" | "confirmed" | "declined"
  | "cancelled" | "completed" | "disputed" | "expired";
export type PaymentStatus =
  | "unpaid" | "authorized" | "deposit_paid" | "paid" | "partially_refunded" | "refunded" | "failed";
export type CancellationPolicy = "flexible" | "moderate" | "strict";

export interface SessionType {
  id: string;
  name: string;
  details: string;
  hourly_rate: number;
  minimum_hours: number;
  includes_engineer: boolean;
}

export interface ServiceAddOn {
  id: string;
  kind: "engineer" | "producer" | "mixing" | "mastering" | "other";
  name: string;
  price: number;
  unit: "per_hour" | "per_session" | "per_track";
}

export interface OpeningHours {
  weekday: number; // 1 = Sunday … 7 = Saturday
  is_closed: boolean;
  opens_at: number; // minutes after midnight
  closes_at: number; // may exceed 1440 (open past midnight)
}

export interface BookingPolicy {
  instant_book?: boolean;
  cancellation_policy?: CancellationPolicy;
  deposit_percent?: number;
  minimum_notice_hours?: number;
  max_advance_days?: number;
  buffer_minutes?: number;
  terms?: string;
}

export interface Studio {
  id: string;
  owner_id: string;
  name: string;
  timezone: string;
  currency: string;
  session_types: SessionType[];
  add_ons: ServiceAddOn[];
  opening_hours: OpeningHours[];
  booking_policy: BookingPolicy;
  status: string;
  is_active: boolean;
}

export interface PriceBreakdown {
  currency: string;
  hourly_rate: number;
  hours: number;
  session_amount: number;
  add_ons_amount: number;
  subtotal: number;
  service_fee: number;
  total: number;
  deposit_amount: number;
  due_now: number;
  due_later: number;
  studio_commission: number;
  studio_payout: number;
}

export interface BookedAddOn {
  id: string;
  name: string;
  quantity: number;
  amount: number;
}

export interface Booking {
  id: string;
  reference: string;
  artist_id: string;
  studio_id: string;
  artist_name: string;
  studio_name: string;
  session_type_id: string;
  session_type_name: string;
  starts_at: string;
  ends_at: string;
  hours: number;
  add_ons: BookedAddOn[];
  status: BookingStatus;
  payment_status: PaymentStatus;
  price: PriceBreakdown;
  notes: string;
  cancellation_reason: string | null;
  cancelled_by: UserRole | null;
  refund_amount: number;
  has_review: boolean;
  payment_intent_id: string | null;
  balance_payment_intent_id: string | null;
  payment_method: "card" | "apple_pay" | "google_pay" | null;
  changed_by: string | null;
  created_at: string;
}

export interface Profile {
  id: string;
  email: string;
  role: UserRole;
  status: "active" | "suspended" | "banned";
  settings: Record<string, unknown>;
  stripe_customer_id: string | null;
}
