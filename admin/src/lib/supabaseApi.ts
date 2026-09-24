import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AdminApi, StudioDecision } from "./api";
import type {
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, Transaction,
} from "./types";

function unwrap<T>(result: { data: T | null; error: { message: string } | null }): T {
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
}

export class SupabaseAdminApi implements AdminApi {
  readonly isDemo = false;
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
}
