// Rows as they come from Supabase (snake_case, dates as ISO strings). Same model as the apps.

export type UserRole = "artist" | "studio_owner" | "admin";
export type AccountStatus = "active" | "suspended" | "banned";

export const ROLE_TITLE: Record<UserRole, string> = { artist: "Artist", studio_owner: "Studio", admin: "Admin" };

export interface UserSettings {
  push_enabled: boolean;
  email_enabled: boolean;
  booking_updates: boolean;
  messages: boolean;
  reminders: boolean;
  review_prompts: boolean;
  marketing: boolean;
  search_radius_km: number;
  use_metric_units: boolean;
}

export const DEFAULT_SETTINGS: UserSettings = {
  push_enabled: true, email_enabled: true, booking_updates: true, messages: true, reminders: true,
  review_prompts: true, marketing: false, search_radius_km: 10, use_metric_units: true,
};

export interface UserAccount {
  id: string;
  email: string;
  role: UserRole;
  status: AccountStatus;
  is_verified?: boolean;
  /** Set once the "Confirm your email" link was opened (or right away for Apple/Google sign-ups). */
  email_verified_at?: string | null;
  settings?: Partial<UserSettings>;
  created_at: string;
  accepted_terms_version?: string | null;
  accepted_terms_at?: string | null;
  status_until?: string | null;
  status_reason?: string | null;
}

export type Genre =
  | "hip_hop" | "rap" | "rnb" | "pop" | "rock" | "indie" | "electronic" | "house" | "techno" | "jazz" | "soul"
  | "classical" | "metal" | "punk" | "folk" | "afro" | "latin" | "reggae" | "greek" | "podcast" | "voice_over" | "other";

export const GENRES: [Genre, string][] = [
  ["hip_hop", "Hip-hop"], ["rap", "Rap"], ["rnb", "R&B"], ["pop", "Pop"], ["rock", "Rock"], ["indie", "Indie"],
  ["electronic", "Electronic"], ["house", "House"], ["techno", "Techno"], ["jazz", "Jazz"], ["soul", "Soul"],
  ["classical", "Classical"], ["metal", "Metal"], ["punk", "Punk"], ["folk", "Folk"], ["afro", "Afro"],
  ["latin", "Latin"], ["reggae", "Reggae"], ["greek", "Greek / Laïká"], ["podcast", "Podcast"],
  ["voice_over", "Voice-over"], ["other", "Other"],
];
export const genreTitle = (g: string) => GENRES.find(([k]) => k === g)?.[1] ?? g;

export type SocialPlatform = "spotify" | "apple_music" | "instagram" | "tiktok" | "youtube" | "soundcloud" | "website";
export const SOCIAL_PLATFORMS: [SocialPlatform, string][] = [
  ["spotify", "Spotify"], ["apple_music", "Apple Music"], ["instagram", "Instagram"], ["tiktok", "TikTok"],
  ["youtube", "YouTube"], ["soundcloud", "SoundCloud"], ["website", "Website"],
];
export const platformTitle = (p: string) => SOCIAL_PLATFORMS.find(([k]) => k === p)?.[1] ?? p;
export const PLATFORM_COLORS: Record<SocialPlatform, [string, string]> = {
  spotify: ["#1CBA54", "#0D8040"], apple_music: ["#FA4269", "#FD704D"], instagram: ["#823BB5", "#FD594D"],
  tiktok: ["#1A1A1F", "#00D4DE"], youtube: ["#FF3333", "#BF0D0D"], soundcloud: ["#FF9919", "#FF5400"], website: ["#7366FF", "#40CCFF"],
};

export interface SocialLink { platform: SocialPlatform; url: string }

export interface ArtistProfile {
  id: string;
  artist_name: string;
  genres: Genre[];
  city: string;
  bio: string;
  avatar_url?: string | null;
  links: SocialLink[];
  is_verified?: boolean;
  has_admin_badge?: boolean | null;
  rating_average?: number | null;
  review_count?: number | null;
  promoted_until?: string | null;
}

export type Facility =
  | "vocal_booth" | "live_room" | "control_room" | "isolation_booth" | "drum_room" | "lounge" | "kitchen" | "wifi"
  | "air_conditioning" | "parking" | "public_transport" | "wheelchair_access" | "smoking_area" | "podcast_setup"
  | "video_recording" | "instruments_available";
export const FACILITIES: [Facility, string][] = [
  ["vocal_booth", "Vocal booth"], ["live_room", "Live room"], ["control_room", "Control room"],
  ["isolation_booth", "Isolation booth"], ["drum_room", "Drum room"], ["lounge", "Lounge"], ["kitchen", "Kitchen"],
  ["wifi", "Wi-Fi"], ["air_conditioning", "Air conditioning"], ["parking", "Parking"],
  ["public_transport", "Near public transport"], ["wheelchair_access", "Wheelchair access"], ["smoking_area", "Smoking area"],
  ["podcast_setup", "Podcast setup"], ["video_recording", "Video recording"], ["instruments_available", "Instruments available"],
];
export const facilityTitle = (f: string) => FACILITIES.find(([k]) => k === f)?.[1] ?? f;

export type EquipmentCategory = "microphone" | "preamp" | "console" | "monitors" | "interface" | "outboard" | "instrument" | "software" | "other";
export const EQUIPMENT_CATEGORIES: [EquipmentCategory, string][] = [
  ["microphone", "Microphones"], ["preamp", "Preamps"], ["console", "Consoles"], ["monitors", "Monitors"],
  ["interface", "Interfaces"], ["outboard", "Outboard gear"], ["instrument", "Instruments"], ["software", "Software"], ["other", "Other"],
];

export type StudioStatus = "draft" | "pending_review" | "changes_requested" | "approved" | "rejected" | "suspended";
export const STUDIO_STATUS_TITLE: Record<StudioStatus, string> = {
  draft: "Draft", pending_review: "Pending review", changes_requested: "Changes requested", approved: "Approved",
  rejected: "Rejected", suspended: "Suspended",
};

export type CancellationPolicy = "flexible" | "moderate" | "strict";
export const CANCELLATION: Record<CancellationPolicy, { title: string; summary: string }> = {
  flexible: { title: "Flexible", summary: "Full refund up to 24 hours before the session." },
  moderate: { title: "Moderate", summary: "Full refund up to 72 hours before, 50% up to 24 hours before." },
  strict: { title: "Strict", summary: "50% refund up to 7 days before the session. No refund after that." },
};

export interface StudioAddress { street: string; postal_code: string; city: string; area: string; country: string }
export interface StudioContact { phone: string; email: string; website: string }
export interface SessionType { id: string; name: string; details: string; hourly_rate: number; minimum_hours: number; includes_engineer: boolean }
export type AddOnKind = "engineer" | "producer" | "mixing" | "mastering" | "other";
export const ADD_ON_KINDS: [AddOnKind, string][] = [["engineer", "Engineer"], ["producer", "Producer"], ["mixing", "Mixing"], ["mastering", "Mastering"], ["other", "Extra"]];
export type PriceUnit = "per_hour" | "per_session" | "per_track";
export const PRICE_UNITS: [PriceUnit, string][] = [["per_hour", "/ hour"], ["per_session", "/ session"], ["per_track", "/ track"]];
export interface ServiceAddOn { id: string; kind: AddOnKind; name: string; price: number; unit: PriceUnit }
export interface EquipmentItem { id: string; category: EquipmentCategory; name: string }
export interface StudioPerson { id: string; name: string; role: string; bio: string }
/** weekday: 1 = Sunday … 7 = Saturday (iOS Calendar). Minutes after midnight; closes_at may exceed 1440. */
export interface OpeningHours { weekday: number; is_closed: boolean; opens_at: number; closes_at: number }

export interface BookingPolicy {
  instant_book: boolean;
  cancellation_policy: CancellationPolicy;
  deposit_percent: number;
  minimum_notice_hours: number;
  max_advance_days: number;
  buffer_minutes: number;
  terms: string;
  accepts_cash: boolean;
  check_in_enabled: boolean;
}

export const DEFAULT_POLICY: BookingPolicy = {
  instant_book: true, cancellation_policy: "moderate", deposit_percent: 0, minimum_notice_hours: 12,
  max_advance_days: 90, buffer_minutes: 0, terms: "", accepts_cash: true, check_in_enabled: true,
};

export interface Studio {
  id: string;
  owner_id: string;
  name: string;
  tagline: string;
  description: string;
  photo_urls: string[];
  video_url?: string | null;
  address: StudioAddress;
  latitude: number;
  longitude: number;
  contact: StudioContact;
  currency: string;
  price_from: number;
  session_types: SessionType[];
  add_ons: ServiceAddOn[];
  facilities: Facility[];
  equipment: EquipmentItem[];
  engineers: StudioPerson[];
  capacity: number;
  genres: Genre[];
  opening_hours: OpeningHours[];
  rules: string[];
  booking_policy: BookingPolicy;
  status: StudioStatus;
  is_active: boolean;
  is_verified?: boolean;
  admin_note?: string | null;
  rating_average: number;
  review_count: number;
  booking_count: number;
  created_at?: string;
  submitted_at?: string | null;
  timezone?: string | null;
  has_admin_badge?: boolean | null;
  admin_tags?: string[] | null;
  promoted_until?: string | null;
  platform_fee_percent?: number | null;
}

export type BookingStatus = "awaiting_payment" | "pending_approval" | "confirmed" | "declined" | "cancelled" | "completed" | "disputed" | "expired";
export const BOOKING_STATUS_TITLE: Record<BookingStatus, string> = {
  awaiting_payment: "Awaiting payment", pending_approval: "Awaiting studio", confirmed: "Confirmed", declined: "Declined",
  cancelled: "Cancelled", completed: "Completed", disputed: "In dispute", expired: "Expired",
};
export type PaymentStatus = "unpaid" | "authorized" | "deposit_paid" | "paid" | "partially_refunded" | "refunded" | "failed" | "pay_at_studio";
export const PAYMENT_STATUS_TITLE: Record<PaymentStatus, string> = {
  unpaid: "Unpaid", authorized: "Card authorised", deposit_paid: "Deposit paid", paid: "Paid",
  partially_refunded: "Partially refunded", refunded: "Refunded", failed: "Payment failed", pay_at_studio: "Pay cash at studio",
};
export type PaymentMethod =
  | "card" | "apple_pay" | "google_pay" | "cash" | "link" | "paypal" | "klarna" | "mobilepay" | "ideal" | "bancontact"
  | "blik" | "eps" | "revolut_pay" | "other";
export const PAYMENT_METHOD_TITLE: Record<PaymentMethod, string> = {
  card: "Card", apple_pay: "Apple Pay", google_pay: "Google Pay", cash: "Cash at the studio", link: "Link", paypal: "PayPal",
  klarna: "Klarna", mobilepay: "MobilePay", ideal: "iDEAL", bancontact: "Bancontact", blik: "BLIK", eps: "EPS",
  revolut_pay: "Revolut Pay", other: "Online payment",
};

export interface BookedAddOn { id: string; name: string; quantity: number; amount: number }
export interface PriceBreakdown {
  currency: string; hourly_rate: number; hours: number; session_amount: number; add_ons_amount: number; subtotal: number;
  service_fee: number; total: number; deposit_amount: number; due_now: number; due_later: number;
  studio_commission: number; studio_payout: number;
  /** Discounts (server-computed): studio offers and promo codes. An EasySesh code is a negative service_fee. */
  original_subtotal?: number; offer_discount?: number; promo_discount?: number; promo_code?: string | null;
  discounts?: PriceDiscount[];
}
export interface PriceDiscount { label: string; percent: number; amount: number; kind: "offer" | "studio_code" | "easysesh_code" }

/** A studio's automatic deal, e.g. "Mixing 50% off". */
export type OfferTarget = "everything" | "sessions" | "add_ons" | "session_type" | "add_on";
export interface StudioOffer {
  id: string; studio_id: string; title: string; percent_off: number; applies_to: OfferTarget; target_id: string | null;
  ends_at: string | null; is_active: boolean; created_at: string;
}
/** A code typed in at checkout. studio_id null = an EasySesh code (made by an admin, paid by EasySesh). */
export interface PromoCode {
  id: string; code: string; studio_id: string | null; percent_off: number; description: string; starts_at: string; ends_at: string | null;
  max_uses: number | null; max_uses_per_user: number; is_active: boolean; created_at: string; uses?: number;
}
export interface PromoCheck { code: string; percent_off: number; description: string; by_easysesh: boolean; ends_at: string | null }

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
  cancellation_reason?: string | null;
  cancelled_by?: UserRole | null;
  refund_amount: number;
  has_review: boolean;
  created_at: string;
  payment_method?: PaymentMethod | null;
  cash_received_at?: string | null;
  artist_checked_in_at?: string | null;
  artist_check_in_distance_m?: number | null;
  studio_confirmed_arrival_at?: string | null;
}

export interface PaymentTransaction {
  id: string; booking_id: string; kind: "charge" | "balance" | "refund"; method: PaymentMethod; status: "pending" | "succeeded" | "failed";
  amount: number; platform_fee: number; currency: string; receipt_number: string; card_brand?: string | null; card_last4?: string | null;
  failure_reason?: string | null; created_at: string;
}

export type PayoutStatus = "scheduled" | "in_transit" | "paid" | "failed";
export const PAYOUT_STATUS_TITLE: Record<PayoutStatus, string> = { scheduled: "Scheduled", in_transit: "On the way", paid: "Paid", failed: "Failed" };
export interface Payout { id: string; studio_id: string; amount: number; currency: string; status: PayoutStatus; scheduled_for: string; paid_at?: string | null }

export type FeeKind = "cash_commission" | "payout_offset" | "invoice_payment" | "manual_payment" | "waiver";
export const FEE_KIND_TITLE: Record<FeeKind, string> = {
  cash_commission: "Platform fee (cash booking)", payout_offset: "Deducted from payout", invoice_payment: "Invoice paid",
  manual_payment: "Payment received", waiver: "Waived",
};
export interface FeeLedgerEntry { id: string; studio_id: string; booking_id?: string | null; kind: FeeKind; amount: number; currency: string; note?: string | null; created_at: string }
export interface FeeInvoice { id: string; studio_id: string; amount: number; currency: string; status: string; hosted_invoice_url?: string | null; due_at?: string | null; created_at: string }

export interface BlockedSlot { id: string; studio_id: string; starts_at: string; ends_at: string; reason: string }
export interface PayoutAccount { studio_id: string; account_holder: string; iban_last4: string; stripe_account_id?: string | null; payouts_enabled: boolean }

export type ConversationRequestStatus = "accepted" | "pending" | "declined";
export interface Conversation {
  id: string; artist_id: string; studio_id: string; booking_id?: string | null; artist_name: string; studio_name: string;
  studio_photo_url?: string | null; last_message_preview: string; last_message_at: string; artist_unread: number; studio_unread: number;
  request_status?: ConversationRequestStatus | null; started_by_studio?: boolean | null; artist_avatar_url?: string | null;
}
export interface ChatMessage { id: string; conversation_id: string; sender_id?: string | null; kind: "text" | "system" | "booking"; body: string; created_at: string }
/** An artist in the studios' "Find artists" list (discover_artists). */
export interface DiscoveredArtist {
  id: string; artist_name: string; city: string; genres: string[]; avatar_url?: string | null; bio: string; is_verified: boolean;
  has_admin_badge: boolean; rating_average: number; review_count: number; session_count: number; is_promoted: boolean;
  has_booked: boolean; joined_at: string;
}
export interface ArtistSearchResult { id: string; artist_name: string; city: string; genres: string[]; avatar_url?: string | null; is_verified: boolean; has_booked: boolean; has_admin_badge?: boolean | null; is_promoted?: boolean | null }

export interface Review {
  id: string; booking_id: string; studio_id: string; artist_id: string; artist_name: string; rating: number;
  facilities_rating: number; experience_rating: number; engineer_rating?: number | null; text: string;
  studio_reply?: string | null; studio_replied_at?: string | null; created_at: string;
}
export interface ArtistReview { id: string; booking_id: string; studio_id: string; artist_id: string; studio_name: string; rating: number; text: string; created_at: string }

export type NotificationKind =
  | "booking_confirmed" | "booking_changed" | "booking_cancelled" | "booking_declined" | "session_reminder" | "refund_issued"
  | "review_reminder" | "booking_requested" | "new_review" | "payout_sent" | "studio_approved" | "studio_rejected"
  | "studio_changes_requested" | "new_message" | "system";
export interface AppNotification {
  id: string; user_id: string; kind: NotificationKind; title: string; body: string; is_read: boolean;
  booking_id?: string | null; conversation_id?: string | null; studio_id?: string | null; created_at: string;
}

export type ReportTarget = "user" | "studio" | "review" | "message" | "booking";
export const REPORT_TITLE: Record<ReportTarget, string> = {
  user: "Report user", studio: "Report studio", review: "Report review", message: "Report message", booking: "Report booking",
};
export type ReportReason = "fake" | "spam" | "abusive" | "inappropriate" | "fraud" | "no_show" | "other";
export const REPORT_REASONS: [ReportReason, string, string][] = [
  ["fake", "Fake or misleading", "Fake profile, photos or information"],
  ["spam", "Spam", "Advertising, repeated or unwanted messages"],
  ["abusive", "Abusive or harassing", "Insults, threats or harassment"],
  ["inappropriate", "Inappropriate content", "Offensive, sexual or violent content"],
  ["fraud", "Fraud or scam", "Asking to pay outside EasySesh, scams or stolen cards"],
  ["no_show", "No-show", "Didn't turn up or the studio was closed"],
  ["other", "Something else", "Anything else that breaks our rules"],
];

export type SupportCategory = "account" | "booking" | "payment" | "studio" | "bug" | "other";
export const SUPPORT_CATEGORIES: [SupportCategory, string][] = [
  ["account", "Account & login"], ["booking", "A booking"], ["payment", "Payments & refunds"],
  ["studio", "My studio listing"], ["bug", "Something isn't working"], ["other", "Something else"],
];
export type SupportStatus = "open" | "answered" | "closed";
export const SUPPORT_STATUS_TITLE: Record<SupportStatus, string> = { open: "Waiting for EasySesh", answered: "EasySesh replied", closed: "Closed" };
export interface SupportTicket {
  id: string; user_id: string; subject: string; category: SupportCategory; booking_id?: string | null; status: SupportStatus;
  user_unread: number; last_message_preview: string; last_message_at: string; created_at: string; rating?: number | null; rating_comment?: string | null;
}
export interface SupportMessage { id: string; ticket_id: string; sender_id?: string | null; from_admin: boolean; body: string; created_at: string }

export type PromotionStatus = "pending" | "active" | "expired" | "cancelled";
export const PROMOTION_STATUS_TITLE: Record<PromotionStatus, string> = { pending: "Waiting for payment", active: "Active", expired: "Ended", cancelled: "Cancelled" };
export const PROMOTION_PACKAGE_TITLE: Record<string, string> = { week: "1 week", two_weeks: "2 weeks", month: "1 month", custom: "Promotion" };
export const PROMOTION_PACKAGES = ["week", "two_weeks", "month"] as const;
/** Same table as the database's promotion_price (minor units); the database decides the actual charge. */
export function promotionPrice(pkg: string, currency: string): number {
  const table: Record<string, [number, number, number]> = {
    DKK: [14900, 26900, 44900], SEK: [21900, 39900, 65900], NOK: [21900, 39900, 65900], GBP: [1600, 2900, 4900],
    USD: [2100, 3900, 6500], PLN: [8900, 15900, 25900],
  };
  const row = table[currency.toUpperCase()] ?? [1900, 3500, 5900];
  return row[PROMOTION_PACKAGES.indexOf(pkg as typeof PROMOTION_PACKAGES[number])] ?? 0;
}
export interface StudioPromotion { id: string; studio_id?: string | null; artist_id?: string | null; package: string; days: number; amount: number; currency: string; status: PromotionStatus; starts_at?: string | null; ends_at?: string | null; created_at: string }
export interface StudioArtistLink { studio_id: string; artist_id: string; status: string; created_at: string }

export type BlockState = "none" | "by_me" | "by_them";
export interface BlockedUser { user_id: string; display_name: string; avatar_url?: string | null; blocked_at: string }
export interface ModerationWarning { id: string; reason: string; created_at: string; acknowledged_at?: string | null }
/** A warning, suspension or ban on the account (moderation_actions). */
export interface ModerationRecord { id: string; action: string; reason: string; ends_at: string | null; created_at: string; studio_id: string | null }
/** "Changes to your account" made by the EasySesh team (also emailed). */
export interface AccountChangeNotice { id: string; changes: string[]; reason: string | null; created_at: string }
export interface ChangelogEntry { id: string; version: string; title: string; body: string; audience: string; is_legal_update: boolean; published_at: string }

export interface PaymentIntentInfo { client_secret: string; amount: number; currency: string; capture_later: boolean }
export interface Interval { start: Date; end: Date }

/** A banner from the EasySesh team at the top of the site (outage, announcement…). */
export interface SiteBanner {
  id: string; kind: "info" | "warning" | "outage" | "success"; audience: "everyone" | "guests" | "artist" | "studio_owner";
  title: string; body: string; link_url: string | null; link_label: string | null; ends_at: string | null; dismissible: boolean;
}
