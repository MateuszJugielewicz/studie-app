import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AdminApi, StudioDecision } from "./api";
import type {
  FeeBalance, FeeInvoice, MfaState,
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, SupportMessage, SupportStatus, SupportTicket, Transaction,
} from "./types";

function unwrap<T>(result: { data: T | null; error: { message: string } | null }): T {
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
}

export class SupabaseAdminApi implements AdminApi {
  private client: SupabaseClient;

  constructor(url: string, anonKey: string) {
    this.client = createClient(url, anonKey);
  }

  async signIn(email: string, password: string) {
    const { error } = await this.client.auth.signInWithPassword({ email, password });
    if (error) throw new Error(error.message);
    if (!(await this.currentAdminEmail())) {
      await this.client.auth.signOut();
      throw new Error("This account is not an admin.");
    }
  }

  async mfaState(): Promise<MfaState> {
    const { data: aal } = await this.client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal?.currentLevel === "aal2") return { kind: "verified" };
    const { data: factors } = await this.client.auth.mfa.listFactors();
    const verified = factors?.totp.find((f) => f.status === "verified");
    if (verified) return { kind: "verify", factorId: verified.id };
    // Remove half-finished enrolments before starting a new one.
    for (const factor of factors?.all ?? []) {
      if (factor.status === "unverified") await this.client.auth.mfa.unenroll({ factorId: factor.id });
    }
    const { data, error } = await this.client.auth.mfa.enroll({ factorType: "totp", friendlyName: "EasySesh admin" });
    if (error || !data) throw new Error(error?.message ?? "Could not start two-factor setup.");
    return { kind: "enroll", factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret };
  }

  async verifyMfa(factorId: string, code: string) {
    const { error } = await this.client.auth.mfa.challengeAndVerify({ factorId, code });
    if (error) throw new Error(error.message);
  }

  async signOut() {
    await this.client.auth.signOut();
  }

  async currentAdminEmail() {
    const { data } = await this.client.auth.getUser();
    if (!data.user) return null;
    const { data: profile } = await this.client.from("profiles").select("role, status, email").eq("id", data.user.id).single();
    return profile?.role === "admin" && profile.status === "active" ? (profile.email as string) : null;
  }

  async stats(days: number): Promise<DashboardStats> {
    const from = new Date(Date.now() - days * 86_400_000).toISOString();
    return unwrap(await this.client.rpc("admin_dashboard_stats", { p_from: from, p_to: new Date().toISOString() }));
  }

  async users(): Promise<AdminUser[]> {
    return unwrap(await this.client.from("admin_users").select("*").order("created_at", { ascending: false }).limit(1000));
  }

  async setUserStatus(userId: string, status: AccountStatus, reason?: string) {
    unwrap(await this.client.rpc("admin_set_user_status", { p_user_id: userId, p_status: status, p_reason: reason ?? null }));
  }

  async verifyUser(userId: string, verified: boolean) {
    unwrap(await this.client.rpc("admin_verify_user", { p_user_id: userId, p_verified: verified }));
  }

  async studios(): Promise<Studio[]> {
    return unwrap(await this.client.from("studios").select("*").order("submitted_at", { ascending: false, nullsFirst: false }));
  }

  async studioEvents(studioId: string): Promise<StudioEvent[]> {
    return unwrap(await this.client.from("studio_status_events").select("*").eq("studio_id", studioId).order("created_at", { ascending: false }));
  }

  async reviewStudio(studioId: string, decision: StudioDecision, note?: string) {
    unwrap(await this.client.rpc("admin_review_studio", { p_studio_id: studioId, p_decision: decision, p_note: note ?? null }));
  }

  async setStudioState(studioId: string, patch: { active?: boolean; verified?: boolean; suspended?: boolean; note?: string }) {
    unwrap(await this.client.rpc("admin_set_studio_state", {
      p_studio_id: studioId,
      p_active: patch.active ?? null,
      p_verified: patch.verified ?? null,
      p_suspended: patch.suspended ?? null,
      p_note: patch.note ?? null,
    }));
  }

  async updateStudio(studioId: string, patch: Partial<Pick<Studio, "name" | "tagline" | "description" | "capacity" | "rules">>) {
    unwrap(await this.client.from("studios").update(patch).eq("id", studioId));
  }

  async bookings(): Promise<Booking[]> {
    return unwrap(await this.client.from("bookings").select("*").neq("status", "awaiting_payment").order("created_at", { ascending: false }).limit(1000));
  }

  async disputes(): Promise<Dispute[]> {
    return unwrap(await this.client.from("disputes").select("*").order("created_at", { ascending: false }));
  }

  async refund(bookingId: string, amount: number | undefined, reason: string) {
    const { error } = await this.client.functions.invoke("admin-refund", { body: { booking_id: bookingId, amount, reason } });
    if (error) throw new Error(error.message);
  }

  async resolveDispute(disputeId: string, resolution: string, bookingStatus: BookingStatus) {
    unwrap(await this.client.rpc("admin_resolve_dispute", { p_dispute_id: disputeId, p_resolution: resolution, p_booking_status: bookingStatus }));
  }

  async transactions(): Promise<Transaction[]> {
    return unwrap(await this.client.from("transactions").select("*").order("created_at", { ascending: false }).limit(1000));
  }

  async payouts(): Promise<Payout[]> {
    return unwrap(await this.client.from("payouts").select("*").order("scheduled_for", { ascending: false }).limit(1000));
  }

  async feeBalances(): Promise<FeeBalance[]> {
    return unwrap(await this.client.from("studio_fee_balances").select("*").order("balance", { ascending: false }));
  }

  async feeInvoices(): Promise<FeeInvoice[]> {
    return unwrap(await this.client.from("studio_fee_invoices").select("*").order("created_at", { ascending: false }));
  }

  async recordFeeSettlement(studioId: string, amount: number, currency: string, kind: "manual_payment" | "waiver", note: string) {
    unwrap(await this.client.rpc("admin_record_fee_settlement", { p_studio_id: studioId, p_amount: amount, p_currency: currency, p_kind: kind, p_note: note }));
  }

  async sendFeeInvoice(studioId: string, currency: string) {
    const { error } = await this.client.functions.invoke("studio-fee-invoice", { body: { studio_id: studioId, currency } });
    if (error) throw new Error(error.message);
  }

  async reports(): Promise<Report[]> {
    return unwrap(await this.client.from("reports").select("*").order("created_at", { ascending: false }));
  }

  async reportTarget(report: Report): Promise<ReportTargetDetails> {
    switch (report.target_type) {
      case "user": {
        const { data } = await this.client.from("admin_users").select("*").eq("id", report.target_id).maybeSingle();
        return { title: data ? `${data.artist_name || data.studio_name || data.email} (${data.role})` : "Unknown user", userId: report.target_id };
      }
      case "studio": {
        const { data } = await this.client.from("studios").select("name, owner_id").eq("id", report.target_id).maybeSingle();
        return { title: data?.name ?? "Unknown studio", studioId: report.target_id, userId: data?.owner_id };
      }
      case "review": {
        const { data } = await this.client.from("reviews").select("*").eq("id", report.target_id).maybeSingle();
        return { title: data ? `${data.rating}★ review by ${data.artist_name}` : "Unknown review", body: data?.text, reviewId: report.target_id, userId: data?.artist_id };
      }
      case "message": {
        const { data } = await this.client.from("messages").select("*").eq("id", report.target_id).maybeSingle();
        return { title: "Chat message", body: data?.body, userId: data?.sender_id ?? undefined };
      }
      case "booking": {
        const { data } = await this.client.from("bookings").select("reference, artist_name, studio_name").eq("id", report.target_id).maybeSingle();
        return { title: data ? `${data.reference} · ${data.artist_name} @ ${data.studio_name}` : "Unknown booking" };
      }
    }
  }

  async resolveReport(reportId: string, status: ReportStatus, note?: string) {
    unwrap(await this.client.rpc("admin_resolve_report", { p_report_id: reportId, p_status: status, p_note: note ?? null }));
  }

  async reviews(): Promise<Review[]> {
    return unwrap(await this.client.from("reviews").select("*").order("created_at", { ascending: false }).limit(500));
  }

  async setReviewHidden(reviewId: string, hidden: boolean) {
    unwrap(await this.client.rpc("admin_set_review_hidden", { p_review_id: reviewId, p_hidden: hidden }));
  }

  async supportTickets(): Promise<SupportTicket[]> {
    return unwrap(await this.client.from("admin_support_tickets").select("*").order("last_message_at", { ascending: false }).limit(1000));
  }

  async supportMessages(ticketId: string): Promise<SupportMessage[]> {
    return unwrap(await this.client.from("support_messages").select("*").eq("ticket_id", ticketId).order("created_at"));
  }

  async replyToSupport(ticketId: string, body: string) {
    unwrap(await this.client.rpc("send_support_message", { p_ticket_id: ticketId, p_body: body }));
  }

  async markSupportRead(ticketId: string) {
    unwrap(await this.client.rpc("mark_support_ticket_read", { p_ticket_id: ticketId }));
  }

  async setSupportStatus(ticketId: string, status: SupportStatus) {
    unwrap(await this.client.rpc("set_support_ticket_status", { p_ticket_id: ticketId, p_status: status }));
  }
}
