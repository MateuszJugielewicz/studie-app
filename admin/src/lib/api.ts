import type {
  FeeBalance, FeeInvoice, MfaState,
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, Transaction,
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

  studios(): Promise<Studio[]>;
  studioEvents(studioId: string): Promise<StudioEvent[]>;
  reviewStudio(studioId: string, decision: StudioDecision, note?: string): Promise<void>;
  setStudioState(studioId: string, patch: { active?: boolean; verified?: boolean; suspended?: boolean; note?: string }): Promise<void>;
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
}
