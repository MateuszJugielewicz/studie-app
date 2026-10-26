import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AdminApi, StudioDecision } from "./api";
import { fetchWithReason } from "./reason";
import type {
  AdminStory, PaymentDomainsResult, VerificationRequest,
  FeeBalance, FeeInvoice, MfaState, ChangelogEntry, ModerationEvent, Promotion, PromoCode, RatingDispute, StudioOffer, TermsStatus,
  AuditEntry, CampaignRecipient, EmailCampaign, FlagRule, NewCampaignRecipient, SentEmail, SiteBanner, StaffMember, StaffRank,
  AccountStatus, AdminUser, Booking, BookingStatus, DashboardStats, Dispute, Payout, Report, ReportStatus,
  ReportTargetDetails, Review, Studio, StudioEvent, SupportMessage, SupportStatus, SupportTicket, Transaction,
} from "./types";

/** The message from an edge function's JSON error body, if there is one. */
async function functionError(error: { message: string; context?: unknown }): Promise<string> {
  try {
    const body = await (error.context as Response).json();
    if (body?.error) return body.error;
  } catch { /* not JSON */ }
  return error.message;
}

function unwrap<T>(result: { data: T | null; error: { message: string } | null }): T {
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
}

export class SupabaseAdminApi implements AdminApi {
  private client: SupabaseClient;

  constructor(url: string, anonKey: string) {
    // Same session storage as the rest of the website, so signing in once covers both.
    this.client = createClient(url, anonKey, {
      auth: { flowType: "pkce", detectSessionInUrl: true, persistSession: true, storageKey: "easysesh.auth" },
      global: { fetch: fetchWithReason },
    });
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

  async resetPassword(userId: string, mode: "email" | "temporary") {
    const { data, error } = await this.client.functions.invoke("admin-reset-password", { body: { user_id: userId, mode } });
    if (error) {
      // Edge function errors carry the JSON message in the response body.
      const detail = await (error as { context?: Response }).context?.json?.().catch(() => null);
      throw new Error(detail?.error ?? error.message);
    }
    return data as { email: string; password?: string };
  }

  async setAdminBadge(userId: string, on: boolean) {
    unwrap(await this.client.rpc("admin_set_admin_badge", { p_user_id: userId, p_on: on }));
  }

  async warnUser(userId: string, reason: string, studioId?: string) {
    unwrap(await this.client.rpc("admin_warn", { p_user_id: userId, p_reason: reason, p_studio_id: studioId ?? null }));
  }

  async moderateUser(userId: string, action: "suspend" | "ban" | "lift", days: number | null, reason: string) {
    unwrap(await this.client.rpc("admin_moderate_user", { p_user_id: userId, p_action: action, p_days: days, p_reason: reason || null }));
  }

  async moderateStudio(studioId: string, action: "suspend" | "lift", days: number | null, reason: string) {
    unwrap(await this.client.rpc("admin_moderate_studio", { p_studio_id: studioId, p_action: action, p_days: days, p_reason: reason || null }));
  }

  async clearModerationHistory(userId: string, entryId?: string): Promise<number> {
    return unwrap(await this.client.rpc("admin_clear_moderation_history", { p_user_id: userId, p_entry_id: entryId ?? null }));
  }

  async moderationHistory(filter: { userId?: string; studioId?: string }): Promise<ModerationEvent[]> {
    let query = this.client.from("admin_moderation_history").select("*");
    if (filter.userId && filter.studioId) query = query.or(`user_id.eq.${filter.userId},studio_id.eq.${filter.studioId}`);
    else if (filter.userId) query = query.eq("user_id", filter.userId);
    else if (filter.studioId) query = query.eq("studio_id", filter.studioId);
    return unwrap(await query.order("created_at", { ascending: false }).limit(200));
  }

  async setStudioTags(studioId: string, tags: string[]) {
    unwrap(await this.client.rpc("admin_set_studio_tags", { p_studio_id: studioId, p_tags: tags }));
  }

  async setPlatformFee(studioId: string, percent: number | null) {
    unwrap(await this.client.rpc("admin_set_platform_fee", { p_studio_id: studioId, p_percent: percent }));
  }

  async reinstateStudio(studioId: string) {
    unwrap(await this.client.rpc("admin_reinstate_studio", { p_studio_id: studioId }));
  }

  async promotions(): Promise<Promotion[]> {
    return unwrap(await this.client.from("admin_promotions").select("*").order("created_at", { ascending: false }).limit(500));
  }

  async currentStaff(): Promise<{ id: string; email: string; rank: StaffRank }> {
    const { data } = await this.client.auth.getUser();
    const { data: profile } = await this.client.from("profiles").select("id, email, admin_rank").eq("id", data.user?.id ?? "").single();
    return { id: profile?.id, email: profile?.email, rank: (profile?.admin_rank ?? "admin") as StaffRank };
  }

  async accountEmail(userId: string): Promise<string | null> {
    const { data } = await this.client.from("profiles").select("email").eq("id", userId).maybeSingle();
    return (data?.email as string | undefined) ?? null;
  }

  async team(): Promise<StaffMember[]> {
    return unwrap(await this.client.from("profiles").select("id, email, admin_rank, created_at").eq("role", "admin").order("created_at"))
      .map((p: { id: string; email: string; admin_rank: StaffRank | null; created_at: string }) => ({ ...p, admin_rank: p.admin_rank ?? "admin" }));
  }

  async setRank(email: string, rank: StaffRank | null) {
    unwrap(await this.client.rpc("admin_set_rank", { p_email: email, p_rank: rank }));
  }

  async auditLog(limit = 500): Promise<AuditEntry[]> {
    return unwrap(await this.client.from("admin_audit_log").select("*").order("created_at", { ascending: false }).limit(limit));
  }

  async registerPaymentDomains(): Promise<PaymentDomainsResult> {
    const { data, error } = await this.client.functions.invoke("payment-domains", { body: {} });
    if (error) throw new Error(await functionError(error));
    return data;
  }

  async viewAs(userId: string): Promise<{ access_token: string; refresh_token: string; email: string; role: string }> {
    const { data, error } = await this.client.functions.invoke("admin-view-as", { body: { user_id: userId } });
    if (error) throw new Error(await functionError(error));
    return data;
  }

  async deleteAccount(userId: string): Promise<{ soft: boolean; cancelled: number }> {
    const { data, error } = await this.client.functions.invoke("admin-delete", { body: { user_id: userId } });
    if (error) throw new Error(await functionError(error));
    return data;
  }

  async deleteStudio(studioId: string): Promise<{ removed: boolean; cancelled: number }> {
    const { data, error } = await this.client.functions.invoke("admin-delete", { body: { studio_id: studioId } });
    if (error) throw new Error(await functionError(error));
    return data;
  }

  async sendEmail(email: { from: string; to: string; subject: string; body: string }) {
    const { error } = await this.client.functions.invoke("admin-send-email", { body: email });
    if (error) throw new Error(await functionError(error));
  }

  async sentEmails(): Promise<SentEmail[]> {
    return unwrap(await this.client.from("admin_emails").select("*").order("created_at", { ascending: false }).limit(200));
  }

  async campaigns(): Promise<EmailCampaign[]> {
    return unwrap(await this.client.from("admin_email_campaigns").select("*").order("created_at", { ascending: false }));
  }

  async saveCampaign(campaign: Partial<EmailCampaign> & { name: string }): Promise<string> {
    const { id, name, from_local, subject, body, footer, note, template } = campaign;
    const row = { name, from_local, subject, body, footer, note, ...(id ? {} : { template: template ?? null }) };
    if (id) {
      unwrap(await this.client.from("email_campaigns").update(row).eq("id", id));
      return id;
    }
    const { data: user } = await this.client.auth.getUser();
    return unwrap<{ id: string }>(await this.client.from("email_campaigns").insert({ ...row, created_by: user.user?.id }).select("id").single()).id;
  }

  async campaignAudience(template: string): Promise<NewCampaignRecipient[]> {
    const rows = unwrap<{ email: string; name: string; city: string; website: string }[]>(await this.client.rpc("campaign_audience", { p_template: template }));
    return (rows ?? []).map((r) => ({ ...r, source: template }));
  }

  async reviewCampaign(campaignId: string, approve: boolean) {
    unwrap(await this.client.rpc("review_email_campaign", { p_campaign_id: campaignId, p_approve: approve }));
  }

  async deleteCampaign(id: string) {
    unwrap(await this.client.from("email_campaigns").delete().eq("id", id));
  }

  async campaignRecipients(campaignId: string): Promise<CampaignRecipient[]> {
    return unwrap(await this.client.from("email_campaign_recipients").select("*").eq("campaign_id", campaignId).order("created_at").limit(5000));
  }

  async addCampaignRecipients(campaignId: string, recipients: NewCampaignRecipient[]): Promise<number> {
    const existing = new Set((await this.campaignRecipients(campaignId)).map((r) => r.email.toLowerCase()));
    const fresh = recipients.filter((r) => {
      const key = r.email.toLowerCase();
      if (existing.has(key)) return false;
      existing.add(key);
      return true;
    });
    if (fresh.length) unwrap(await this.client.from("email_campaign_recipients").insert(fresh.map((r) => ({ ...r, email: r.email.trim().toLowerCase(), campaign_id: campaignId }))));
    return fresh.length;
  }

  async removeCampaignRecipient(id: string) {
    unwrap(await this.client.from("email_campaign_recipients").delete().eq("id", id));
  }

  async doNotContact(email: string, reason: string) {
    const address = email.trim().toLowerCase();
    unwrap(await this.client.from("email_suppressions").upsert({ email: address, reason }));
    unwrap(await this.client.from("email_campaign_recipients").update({ status: "skipped", error: "Asked not to be contacted" }).eq("status", "pending").eq("email", address));
  }

  async sendCampaign(campaignId: string, mode: "test" | "batch", limit?: number) {
    const { data, error } = await this.client.functions.invoke("admin-campaign-send", { body: { campaign_id: campaignId, mode, limit } });
    if (error) throw new Error(await functionError(error));
    return data;
  }

  async stories(): Promise<AdminStory[]> {
    return unwrap(await this.client.from("admin_stories").select("*").order("created_at", { ascending: false }).limit(200));
  }

  async removeStory(storyId: string) {
    unwrap(await this.client.rpc("remove_story", { p_story_id: storyId }));
  }

  async verificationRequests(): Promise<VerificationRequest[]> {
    return unwrap(await this.client.from("admin_verification_requests").select("*").order("created_at", { ascending: false }).limit(500));
  }

  async reviewVerification(requestId: string, approve: boolean, note: string) {
    unwrap(await this.client.rpc("admin_review_verification", { p_request_id: requestId, p_approve: approve, p_note: note || null }));
  }

  async flagRules(): Promise<FlagRule[]> {
    return unwrap(await this.client.from("content_flag_rules").select("*").order("category").order("created_at"));
  }

  async saveFlagRule(rule: Partial<FlagRule>) {
    const { id, created_at: _c, ...row } = rule;
    if (id) unwrap(await this.client.from("content_flag_rules").update(row).eq("id", id).select());
    else unwrap(await this.client.from("content_flag_rules").insert(row).select());
  }

  async removeFlagRule(id: string) {
    unwrap(await this.client.from("content_flag_rules").delete().eq("id", id).select());
  }

  async banners(): Promise<SiteBanner[]> {
    return unwrap(await this.client.from("site_banners").select("*").order("created_at", { ascending: false }).limit(200));
  }

  async saveBanner(banner: Partial<SiteBanner>) {
    const { id, created_at: _c, ...row } = banner;
    if (id) unwrap(await this.client.from("site_banners").update(row).eq("id", id).select());
    else unwrap(await this.client.from("site_banners").insert(row).select());
  }

  async removeBanner(id: string) {
    unwrap(await this.client.from("site_banners").delete().eq("id", id).select());
  }

  async promoCodes(): Promise<PromoCode[]> {
    const rows = unwrap(await this.client.from("promo_codes").select("*, studios(name)").order("created_at", { ascending: false }).limit(1000)) as (PromoCode & { studios: { name: string } | null })[];
    const usage = unwrap(await this.client.from("promo_code_usage").select("*")) as { promo_code_id: string; uses: number }[];
    return rows.map(({ studios, ...c }) => ({ ...c, studio_name: studios?.name ?? null, uses: usage.find((u) => u.promo_code_id === c.id)?.uses ?? 0 }));
  }

  async savePromoCode(code: Partial<PromoCode>) {
    const { id, uses: _u, studio_name: _s, created_at: _c, ...row } = code;
    if (id) unwrap(await this.client.from("promo_codes").update(row).eq("id", id).select());
    else unwrap(await this.client.from("promo_codes").insert(row).select());
  }

  async removePromoCode(id: string) {
    unwrap(await this.client.from("promo_codes").delete().eq("id", id).select());
  }

  async studioOffers(): Promise<StudioOffer[]> {
    const rows = unwrap(await this.client.from("studio_offers").select("*, studios(name)").order("created_at", { ascending: false }).limit(1000)) as (StudioOffer & { studios: { name: string } | null })[];
    return rows.map(({ studios, ...o }) => ({ ...o, studio_name: studios?.name ?? "" }));
  }

  async setOfferActive(id: string, active: boolean) {
    unwrap(await this.client.from("studio_offers").update({ is_active: active }).eq("id", id).select());
  }

  async activatePromotion(promotionId: string) {
    unwrap(await this.client.rpc("admin_activate_promotion", { p_promotion_id: promotionId }));
  }

  async cancelPromotion(promotionId: string) {
    unwrap(await this.client.rpc("admin_cancel_promotion", { p_promotion_id: promotionId }));
  }

  async grantPromotion(studioId: string, days: number, note?: string) {
    unwrap(await this.client.rpc("admin_grant_promotion", { p_studio_id: studioId, p_days: days, p_note: note ?? null }));
  }

  async endPromotion(studioId: string) {
    unwrap(await this.client.rpc("admin_end_promotion", { p_studio_id: studioId }));
  }

  async grantArtistPromotion(artistId: string, days: number, note?: string) {
    unwrap(await this.client.rpc("admin_grant_artist_promotion", { p_artist_id: artistId, p_days: days, p_note: note ?? null }));
  }

  async endArtistPromotion(artistId: string) {
    unwrap(await this.client.rpc("admin_end_artist_promotion", { p_artist_id: artistId }));
  }

  async ratingDisputes(): Promise<RatingDispute[]> {
    return unwrap(await this.client.from("admin_rating_disputes").select("*").order("created_at", { ascending: false }).limit(500));
  }

  async resolveRatingDispute(disputeId: string, remove: boolean, note?: string) {
    unwrap(await this.client.rpc("admin_resolve_rating_dispute", { p_dispute_id: disputeId, p_remove: remove, p_note: note ?? null }));
  }

  async changelog(): Promise<ChangelogEntry[]> {
    return unwrap(await this.client.from("app_changelog").select("*").order("published_at", { ascending: false }).limit(200));
  }

  async publishChangelog(entry: { version: string; title: string; body: string; audience: ChangelogEntry["audience"]; legalUpdate: boolean }) {
    unwrap(await this.client.rpc("admin_publish_changelog", {
      p_version: entry.version, p_title: entry.title, p_body: entry.body, p_audience: entry.audience, p_legal_update: entry.legalUpdate,
    }));
  }

  async deleteChangelog(id: string) {
    unwrap(await this.client.rpc("admin_delete_changelog", { p_id: id }));
  }

  async termsStatus(): Promise<TermsStatus> {
    return unwrap(await this.client.from("admin_terms_status").select("*").single());
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

  async supportOpenCount(): Promise<number> {
    const { count, error } = await this.client.from("support_tickets").select("id", { count: "exact", head: true }).eq("status", "open");
    if (error) throw new Error(error.message);
    return count ?? 0;
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
