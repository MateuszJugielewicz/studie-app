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
  status_until: string | null;
  is_verified: boolean;
  created_at: string;
  artist_name: string | null;
  artist_city: string | null;
  studio_id: string | null;
  studio_name: string | null;
  has_admin_badge: boolean;
  booking_count: number;
  warning_count: number;
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
  booking_policy: { instant_book?: boolean; cancellation_policy?: string; deposit_percent?: number; terms?: string; accepts_cash?: boolean; check_in_enabled?: boolean };
  has_admin_badge: boolean | null;
  admin_tags: string[] | null;
  promoted_until: string | null;
  platform_fee_percent: number | null;
  suspended_until: string | null;
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
  payment_method: "card" | "apple_pay" | "google_pay" | "cash" | "link" | "paypal" | "klarna" | "mobilepay" | "ideal" | "bancontact" | "blik" | "eps" | "revolut_pay" | "other" | null;
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
  status: "open" | "paid" | "void" | "collections";
  hosted_invoice_url: string | null;
  created_at: string;
  paid_at: string | null;
  due_at: string | null;
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
  method: "card" | "apple_pay" | "google_pay" | "cash" | "link" | "paypal" | "klarna" | "mobilepay" | "ideal" | "bancontact" | "blik" | "eps" | "revolut_pay" | "other";
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

export type SupportStatus = "open" | "answered" | "closed";

export interface SupportTicket {
  id: string;
  user_id: string;
  subject: string;
  category: string;
  booking_id: string | null;
  status: SupportStatus;
  user_unread: number;
  admin_unread: number;
  last_message_preview: string;
  last_message_at: string;
  created_at: string;
  closed_at: string | null;
  rating: number | null;
  rating_comment: string | null;
  user_email: string;
  user_role: UserRole;
  user_name: string;
  booking_reference: string | null;
}

export interface SupportMessage {
  id: string;
  ticket_id: string;
  sender_id: string | null;
  from_admin: boolean;
  body: string;
  created_at: string;
}

/** A promo code. studio_id null = an EasySesh code (valid everywhere, EasySesh pays the discount). */
export interface PromoCode {
  id: string; code: string; studio_id: string | null; studio_name?: string | null; percent_off: number; description: string;
  starts_at: string; ends_at: string | null; max_uses: number | null; max_uses_per_user: number; is_active: boolean; created_at: string; uses?: number;
}
export interface StudioOffer {
  id: string; studio_id: string; studio_name?: string; title: string; percent_off: number; applies_to: string; target_id: string | null;
  ends_at: string | null; is_active: boolean; created_at: string;
}

export interface Promotion {
  id: string;
  /** One of the two: a studio's promotion or an artist profile's. */
  studio_id: string | null;
  artist_id: string | null;
  studio_name: string;
  package: "week" | "two_weeks" | "month" | "custom";
  days: number;
  amount: number;
  currency: string;
  status: "pending" | "active" | "expired" | "cancelled";
  source: "purchase" | "admin";
  starts_at: string | null;
  ends_at: string | null;
  note: string | null;
  created_at: string;
  promoted_until: string | null;
}

export interface RatingDispute {
  id: string;
  review_type: "studio_review" | "artist_review";
  review_id: string;
  reason: string;
  status: "open" | "removed" | "kept";
  admin_note: string | null;
  created_at: string;
  resolved_at: string | null;
  rating: number | null;
  review_text: string | null;
  reviewer_name: string | null;
  rated_name: string | null;
}

export interface ChangelogEntry {
  id: string;
  version: string;
  title: string;
  body: string;
  audience: "all" | "artist" | "studio_owner";
  is_legal_update: boolean;
  published_at: string;
}

export interface TermsStatus { version: string; accepted: number; total: number }

export type ModerationKind = "warning" | "suspension" | "ban" | "lifted" | "report" | "studio_status";

export interface ModerationEvent {
  id: string;
  user_id: string | null;
  studio_id: string | null;
  kind: ModerationKind;
  details: string;
  ends_at: string | null;
  acknowledged_at: string | null;
  created_at: string;
  actor_email: string | null;
}

export type StaffRank = "owner" | "admin" | "support";
export interface FlagRule { id: string; category: "minors" | "off_platform_payment" | "illegal" | "contact_details" | "other"; pattern: string; note: string; is_active: boolean; created_at: string }
export interface StaffMember { id: string; email: string; admin_rank: StaffRank; created_at: string }
export interface AuditEntry {
  id: number; admin_id: string | null; admin_email: string | null; admin_rank: string | null; action: string;
  target_table: string | null; target_id: string | null; affected_user: string | null; reason: string | null;
  details: Record<string, unknown>; created_at: string;
}
export interface EmailCampaign {
  id: string; name: string; from_local: string; subject: string; body: string; footer: string; note: string;
  status: "draft" | "sending" | "done"; created_at: string; updated_at: string;
  template: string | null; reviewed_at: string | null; reviewed_by_email: string | null;
  pending_count: number; sent_count: number; failed_count: number; skipped_count: number;
}
export interface CampaignRecipient {
  id: string; campaign_id: string; email: string; name: string; city: string; website: string; source: string;
  status: "pending" | "sent" | "failed" | "skipped"; error: string | null; sent_at: string | null; created_at: string;
}
export type NewCampaignRecipient = Pick<CampaignRecipient, "email" | "name" | "city" | "website" | "source">;
export interface SentEmail { id: string; sender_email: string | null; from_address: string; to_addresses: string[]; subject: string; body: string; created_at: string }
export interface SiteBanner {
  id: string; kind: "info" | "warning" | "outage" | "success"; audience: "everyone" | "guests" | "artist" | "studio_owner";
  title: string; body: string; link_url: string | null; link_label: string | null; starts_at: string; ends_at: string | null;
  dismissible: boolean; is_active: boolean; created_at: string;
}

/** Stripe's status for each website domain (Apple Pay, Google Pay, Link and PayPal on the web). */
export interface PaymentDomainsResult {
  live: boolean;
  domains: { domain: string; apple_pay: string; google_pay: string; link: string; paypal: string; error: string | null }[];
}

/** An artist's or studio's application for the verified badge (admin_verification_requests). */
export interface VerificationRequest {
  id: string;
  user_id: string;
  studio_id: string | null;
  kind: "artist" | "studio";
  status: "pending" | "approved" | "denied" | "cancelled";
  message: string;
  links: string[];
  staff_note: string | null;
  reviewed_by_email: string | null;
  reviewed_at: string | null;
  created_at: string;
  email: string;
  display_name: string | null;
  photo_url: string | null;
  artist_city: string | null;
  studio_city: string | null;
  booking_count: number;
}

/** A story with its poster, for moderation (admin_stories). */
export interface AdminStory {
  id: string; user_id: string; studio_id: string | null; media_url: string; caption: string; created_at: string; expires_at: string;
  removed_at: string | null; poster_name: string | null; poster_email: string; like_count: number; view_count: number; reply_count: number;
}
