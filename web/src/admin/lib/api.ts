import type {
  FeeBalance, FeeInvoice, MfaState, ChangelogEntry, ModerationEvent, Promotion, PromoCode, RatingDispute, StudioOffer, TermsStatus,
  AuditEntry, FlagRule, SentEmail, SiteBanner, StaffMember, StaffRank,
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, SupportMessage, SupportStatus, SupportTicket, Transaction,
} from "./types";

export type StudioDecision = "approve" | "reject" | "request_changes";

/** Everything the dashboard needs, implemented against Supabase. */
export interface AdminApi {
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  currentAdminEmail(): Promise<string | null>;
  /** Admins must use two-factor authentication (TOTP). */
  mfaState(): Promise<MfaState>;
  verifyMfa(factorId: string, code: string): Promise<void>;

  stats(days: number): Promise<DashboardStats>;

  users(): Promise<AdminUser[]>;
  setUserStatus(userId: string, status: AccountStatus, reason?: string): Promise<void>;
  verifyUser(userId: string, verified: boolean): Promise<void>;
  /** "email" sends a reset link; "temporary" sets and returns a one-time password. */
  resetPassword(userId: string, mode: "email" | "temporary"): Promise<{ email: string; password?: string }>;
  /** Cosmetic "EasySesh team" badge; gives no rights in the app. */
  setAdminBadge(userId: string, on: boolean): Promise<void>;

  // Moderation: warnings, suspensions/bans for a period (days = null means until lifted), history.
  warnUser(userId: string, reason: string, studioId?: string): Promise<void>;
  moderateUser(userId: string, action: "suspend" | "ban" | "lift", days: number | null, reason: string): Promise<void>;
  moderateStudio(studioId: string, action: "suspend" | "lift", days: number | null, reason: string): Promise<void>;
  moderationHistory(filter: { userId?: string; studioId?: string }): Promise<ModerationEvent[]>;

  studios(): Promise<Studio[]>;
  studioEvents(studioId: string): Promise<StudioEvent[]>;
  reviewStudio(studioId: string, decision: StudioDecision, note?: string): Promise<void>;
  setStudioState(studioId: string, patch: { active?: boolean; verified?: boolean; suspended?: boolean; note?: string }): Promise<void>;
  setStudioTags(studioId: string, tags: string[]): Promise<void>;
  /** Special deal: the studio's platform fee in percent; null = standard fee. */
  setPlatformFee(studioId: string, percent: number | null): Promise<void>;
  reinstateStudio(studioId: string): Promise<void>;

  promotions(): Promise<Promotion[]>;
  activatePromotion(promotionId: string): Promise<void>;
  cancelPromotion(promotionId: string): Promise<void>;
  grantPromotion(studioId: string, days: number, note?: string): Promise<void>;
  endPromotion(studioId: string): Promise<void>;

  /** The signed-in staff member and their rank (owner > admin > support). */
  currentStaff(): Promise<{ id: string; email: string; rank: StaffRank }>;
  team(): Promise<StaffMember[]>;
  /** Owners only: add someone (by email) to the team, change their rank, or remove them (null). */
  setRank(email: string, rank: StaffRank | null): Promise<void>;
  /** Owners only. */
  auditLog(limit?: number): Promise<AuditEntry[]>;
  /** A read-only session as this user, for the website's "view as" mode. */
  viewAs(userId: string): Promise<{ access_token: string; refresh_token: string; email: string; role: string }>;
  sendEmail(email: { from: string; to: string; subject: string; body: string }): Promise<void>;
  sentEmails(): Promise<SentEmail[]>;
  /** Word lists for automatic report flags. */
  flagRules(): Promise<FlagRule[]>;
  saveFlagRule(rule: Partial<FlagRule>): Promise<void>;
  removeFlagRule(id: string): Promise<void>;
  banners(): Promise<SiteBanner[]>;
  saveBanner(banner: Partial<SiteBanner>): Promise<void>;
  removeBanner(id: string): Promise<void>;

  /** All promo codes (EasySesh's and studios'), with how often they were used. */
  promoCodes(): Promise<PromoCode[]>;
  savePromoCode(code: Partial<PromoCode>): Promise<void>;
  removePromoCode(id: string): Promise<void>;
  studioOffers(): Promise<StudioOffer[]>;
  setOfferActive(id: string, active: boolean): Promise<void>;

  ratingDisputes(): Promise<RatingDispute[]>;
  resolveRatingDispute(disputeId: string, remove: boolean, note?: string): Promise<void>;

  changelog(): Promise<ChangelogEntry[]>;
  publishChangelog(entry: { version: string; title: string; body: string; audience: ChangelogEntry["audience"]; legalUpdate: boolean }): Promise<void>;
  deleteChangelog(id: string): Promise<void>;
  termsStatus(): Promise<TermsStatus>;

  updateStudio(studioId: string, patch: Partial<Pick<Studio, "name" | "tagline" | "description" | "capacity" | "rules">>): Promise<void>;

  bookings(): Promise<Booking[]>;
  disputes(): Promise<Dispute[]>;
  refund(bookingId: string, amount: number | undefined, reason: string): Promise<void>;
  resolveDispute(disputeId: string, resolution: string, bookingStatus: BookingStatus): Promise<void>;

  transactions(): Promise<Transaction[]>;
  payouts(): Promise<Payout[]>;
  feeBalances(): Promise<FeeBalance[]>;
  feeInvoices(): Promise<FeeInvoice[]>;
  recordFeeSettlement(studioId: string, amount: number, currency: string, kind: "manual_payment" | "waiver", note: string): Promise<void>;
  sendFeeInvoice(studioId: string, currency: string): Promise<void>;

  reports(): Promise<Report[]>;
  reportTarget(report: Report): Promise<ReportTargetDetails>;
  resolveReport(reportId: string, status: ReportStatus, note?: string): Promise<void>;
  reviews(): Promise<Review[]>;
  setReviewHidden(reviewId: string, hidden: boolean): Promise<void>;

  supportTickets(): Promise<SupportTicket[]>;
  /** Tickets waiting for an admin reply (for the sidebar badge). */
  supportOpenCount(): Promise<number>;
  supportMessages(ticketId: string): Promise<SupportMessage[]>;
  replyToSupport(ticketId: string, body: string): Promise<void>;
  markSupportRead(ticketId: string): Promise<void>;
  setSupportStatus(ticketId: string, status: SupportStatus): Promise<void>;
}
