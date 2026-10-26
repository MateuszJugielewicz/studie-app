// The website's backend calls: the same tables, database functions and edge functions as the apps
// (android/.../data/Backend.kt, ios/EasySesh/Services/SupabaseBackend.swift).
import { createClient, type RealtimeChannel, type SupabaseClient } from "@supabase/supabase-js";
import { config, TERMS_VERSION } from "./config";
import { format, t } from "./i18n";
import { passwordProblem, Studios, uuid } from "./core";
import { endViewAs, takeViewAsTokens, viewAs, viewOnlyFetch } from "./viewAs";
import type {
  AppNotification, ArtistProfile, ArtistReview, ArtistSearchResult, BlockState, BlockedSlot, BlockedUser, Booking, ChangelogEntry,
  ChatMessage, Conversation, FeeInvoice, FeeLedgerEntry, Interval, ModerationWarning, PaymentIntentInfo, PaymentTransaction, Payout,
  DiscoveredArtist, PayoutAccount, StudioBusiness, Story, StoryActivity, StoryAuthor, VerificationRequest, ReportReason, ReportTarget, Review, Studio, StudioArtistLink, StudioPromotion, SupportCategory, SupportMessage,
  SupportTicket, UserAccount, UserRole, UserSettings, PriceBreakdown, PromoCheck, PromoCode, SiteBanner, StudioOffer, ModerationRecord, AccountChangeNotice,
} from "./types";

/** An error whose message is shown to the user (already translated). */
export class AppError extends Error {}

const MESSAGES: Record<string, string> = {
  slot_unavailable: "That time is no longer available. Please pick another slot.",
  forbidden: "You don't have access to this.",
  not_found: "We couldn't find that.",
  account_suspended: "This account is suspended. Contact support.",
};

function mapMessage(message: string, code?: string): AppError {
  if (MESSAGES[message]) return new AppError(t(MESSAGES[message]));
  if (code === "23P01") return new AppError(t(MESSAGES.slot_unavailable));
  if (code === "42501") return new AppError(t(MESSAGES.forbidden));
  if (/invalid login/i.test(message)) return new AppError(t("Wrong email or password."));
  if (/already registered/i.test(message)) return new AppError(t("An account with this email already exists."));
  return new AppError(t(message || "Something went wrong. Please try again."));
}

/** The text to show for any error (like `error.userMessage` in the apps). */
export function userMessage(error: unknown): string {
  if (error instanceof AppError) return error.message;
  if (error instanceof Error) return t(error.message || "Something went wrong. Please try again.");
  return t("Something went wrong. Please try again.");
}

type Result<T> = { data: T | null; error: { message: string; code?: string } | null };
/** [{ id, quantity }] for the booking RPCs. */
const addOnList = (addOns: Record<string, number>) => Object.entries(addOns).filter(([, q]) => q > 0).map(([id, quantity]) => ({ id, quantity }));

function unwrap<T>(result: Result<T>): T {
  if (result.error) throw mapMessage(result.error.message, result.error.code);
  return result.data as T;
}

export function restrictionMessage(account: UserAccount): string {
  const parts = [t(account.status === "banned" ? "This account is banned." : "This account is suspended.")];
  if (account.status_until) {
    parts.push(format("Until %@.", new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(account.status_until))));
  } else parts.push(t("Contact support if you think this is a mistake."));
  if (account.status_reason) parts.push(format("Reason: %@", account.status_reason));
  return parts.join(" ");
}

export const authRedirect = () => `${window.location.origin}/auth/callback`;

export class Api {
  readonly client: SupabaseClient;

  constructor() {
    const viewing = viewAs();
    this.client = createClient(config.supabaseUrl, config.supabaseAnonKey || "missing", viewing ? {
      // Read-only session opened from the admin panel: this tab only, writes refused.
      auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, storageKey: "easysesh.viewas", storage: window.sessionStorage },
      global: { fetch: viewOnlyFetch },
    } : {
      auth: { flowType: "pkce", detectSessionInUrl: true, persistSession: true, storageKey: "easysesh.auth" },
    });
  }

  private async userId(): Promise<string> {
    const { data } = await this.client.auth.getSession();
    const id = data.session?.user.id;
    if (!id) throw new AppError(t("Please sign in to continue."));
    return id;
  }

  private async rpc<T>(fn: string, params: Record<string, unknown> = {}): Promise<T> {
    return unwrap(await this.client.rpc(fn, params)) as T;
  }

  /** Calls an edge function (same JSON contract as the apps). */
  private async invoke<T>(fn: string, body: Record<string, unknown>): Promise<T> {
    if (viewAs()) throw new AppError("View only: you're seeing EasySesh as this user, so nothing can be changed.");
    const { data } = await this.client.auth.getSession();
    const response = await fetch(`${config.supabaseUrl}/functions/v1/${fn}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: config.supabaseAnonKey,
        Authorization: `Bearer ${data.session?.access_token ?? config.supabaseAnonKey}`,
      },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    const json = text ? JSON.parse(text) : {};
    if (!response.ok) throw mapMessage(json.error ?? "Request failed.");
    return json as T;
  }

  private async account(id: string): Promise<UserAccount> {
    return unwrap(await this.client.from("profiles").select("*").eq("id", id).single());
  }

  private async ensureActive(account: UserAccount): Promise<UserAccount> {
    let result = account;
    // A suspension whose period is over is lifted right away instead of waiting for the job.
    if (result.status !== "active" && result.status_until && new Date(result.status_until).getTime() <= Date.now()) {
      result = (await this.rpc<UserAccount>("lift_my_expired_restriction").catch(() => null)) ?? result;
    }
    if (result.status !== "active") {
      await this.signOut();
      throw new AppError(restrictionMessage(result));
    }
    return result;
  }

  // MARK: Auth

  async restoreSession(): Promise<UserAccount | null> {
    const tokens = takeViewAsTokens();
    if (tokens) await this.client.auth.setSession(tokens).catch(() => undefined);
    const { data } = await this.client.auth.getSession();
    const user = data.session?.user;
    if (!user) return null;
    try { return await this.ensureActive(await this.account(user.id)); } catch { return null; }
  }

  async signUp(email: string, password: string, role: UserRole): Promise<UserAccount> {
    const problem = passwordProblem(password);
    if (problem) throw new AppError(problem);
    // The sign-up form requires accepting the terms; the version is stored as the consent record.
    const result = await this.client.auth.signUp({
      email, password, options: { emailRedirectTo: authRedirect(), data: { role, terms_version: TERMS_VERSION } },
    });
    if (result.error) throw mapMessage(result.error.message);
    if (!result.data.session) throw new AppError(t("We sent you a confirmation email. Open the link, then sign in."));
    return this.account(result.data.session.user.id);
  }

  /** Sends the "Confirm your email" email again (rate limited by the server). */
  async resendVerificationEmail(): Promise<void> {
    await this.rpc("resend_email_verification");
  }

  /** Re-reads the signed-in user's profile (e.g. after they confirmed their email in another tab). */
  async currentAccount(): Promise<UserAccount | null> {
    const { data } = await this.client.auth.getSession();
    return data.session?.user ? this.account(data.session.user.id).catch(() => null) : null;
  }

  /** The link from the email; works signed in or out. */
  async verifyEmail(token: string): Promise<boolean> {
    return this.rpc<boolean>("verify_email", { p_token: token });
  }

  async signIn(email: string, password: string): Promise<UserAccount> {
    const { data, error } = await this.client.auth.signInWithPassword({ email, password });
    if (error) throw mapMessage(error.message);
    return this.ensureActive(await this.account(data.user.id));
  }

  /** Apple / Google in the browser; the provider sends people back to /auth/callback. */
  async startOAuth(provider: "apple" | "google", role: UserRole): Promise<void> {
    try { localStorage.setItem("easysesh.oauthRole", role); } catch { /* ignore */ }
    const { error } = await this.client.auth.signInWithOAuth({ provider, options: { redirectTo: authRedirect() } });
    if (error) throw mapMessage(error.message);
  }

  /** Social sign-up creates an artist by default; brand-new accounts may switch to studio owner once. */
  async finishSocialSignIn(): Promise<UserAccount | null> {
    let role: string | null = null;
    try { role = localStorage.getItem("easysesh.oauthRole"); localStorage.removeItem("easysesh.oauthRole"); } catch { /* ignore */ }
    if (role === "studio_owner") await this.rpc("claim_role", { p_role: role }).catch(() => undefined);
    const id = (await this.client.auth.getSession()).data.session?.user.id;
    return id ? this.ensureActive(await this.account(id)) : null;
  }

  async sendPasswordReset(email: string) {
    const { error } = await this.client.auth.resetPasswordForEmail(email, { redirectTo: `${authRedirect()}?type=recovery` });
    if (error) throw mapMessage(error.message);
  }

  async signOut() {
    // Leaving view-as only ends that session (a global sign-out would sign the real person out everywhere).
    if (viewAs()) {
      await this.client.auth.signOut({ scope: "local" }).catch(() => undefined);
      endViewAs();
      return;
    }
    await this.client.auth.signOut().catch(() => undefined);
  }

  async changePassword(password: string) {
    const problem = passwordProblem(password);
    if (problem) throw new AppError(problem);
    const { error } = await this.client.auth.updateUser({ password });
    if (error) throw mapMessage(error.message);
  }

  async deleteAccount() {
    await this.invoke("delete-account", {});
    await this.signOut();
  }

  acceptTerms = (version: string) => this.rpc<UserAccount>("accept_terms", { p_version: version });
  exportPersonalData = async () => JSON.stringify(await this.rpc<unknown>("export_my_data"), null, 2);

  async updateSettings(settings: UserSettings): Promise<UserAccount> {
    const id = await this.userId();
    return unwrap(await this.client.from("profiles").update({ settings }).eq("id", id).select().single());
  }

  // MARK: Profiles

  async artistProfile(id: string): Promise<ArtistProfile | null> {
    return unwrap(await this.client.from("artist_profiles").select("*").eq("id", id).maybeSingle());
  }

  async saveArtistProfile(profile: ArtistProfile): Promise<ArtistProfile> {
    const { rating_average: _a, review_count: _b, is_verified: _c, has_admin_badge: _d, ...row } = profile;
    return unwrap(await this.client.from("artist_profiles").upsert(row).select().single());
  }

  /** Uploads a JPEG (already resized) under the caller's own folder, as the storage policies require. */
  async uploadImage(blob: Blob, folder: string): Promise<string> {
    const id = await this.userId();
    const path = `${id.toLowerCase()}/${folder}/${uuid().toLowerCase()}.jpg`;
    const bucket = this.client.storage.from("media");
    const { error } = await bucket.upload(path, blob, { upsert: false, contentType: "image/jpeg" });
    if (error) throw mapMessage(error.message);
    return bucket.getPublicUrl(path).data.publicUrl;
  }

  // MARK: Studios

  async publishedStudios(): Promise<Studio[]> {
    return unwrap(await this.client.from("studios").select("*").eq("status", "approved").eq("is_active", true).order("name"));
  }

  async studio(id: string): Promise<Studio> {
    return unwrap(await this.client.from("studios").select("*").eq("id", id).single());
  }

  async ownedStudio(): Promise<Studio | null> {
    const id = await this.userId();
    return unwrap(await this.client.from("studios").select("*").eq("owner_id", id).limit(1).maybeSingle());
  }

  /** Moderation columns are protected by a trigger; the owner can only change listing content. */
  async saveStudio(studio: Studio): Promise<Studio> {
    return unwrap(await this.client.from("studios").upsert(Studios.normalized(studio)).select().single());
  }

  submitStudioForReview = (id: string) => this.rpc<Studio>("submit_studio_for_review", { p_studio_id: id });
  setStudioActive = (id: string, active: boolean) => this.rpc<Studio>("set_studio_active", { p_studio_id: id, p_active: active });

  async studioBusiness(studioId: string): Promise<StudioBusiness | null> {
    return unwrap(await this.client.from("studio_business_details").select("studio_id, cvr").eq("studio_id", studioId).maybeSingle());
  }

  async saveStudioBusiness(studioId: string, cvr: string): Promise<void> {
    unwrap(await this.client.from("studio_business_details").upsert({ studio_id: studioId, cvr: cvr.trim(), updated_at: new Date().toISOString() }));
  }

  async payoutAccount(studioId: string): Promise<PayoutAccount | null> {
    return unwrap(await this.client.from("studio_payout_accounts").select("*").eq("studio_id", studioId).maybeSingle());
  }

  /** Stripe's hosted onboarding (identity + bank details). It returns to the website's payout page. */
  async payoutOnboardingUrl(studioId: string, holder: string): Promise<string | null> {
    const r = await this.invoke<{ onboarding_url?: string | null }>("payout-account", { studio_id: studioId, account_holder: holder, action: "onboarding_link", client: "web" });
    return r.onboarding_url ?? null;
  }

  async syncPayoutAccount(studioId: string): Promise<PayoutAccount> {
    return (await this.invoke<{ account: PayoutAccount }>("payout-account", { studio_id: studioId, action: "sync" })).account;
  }

  async savePayoutBank(studioId: string, holder: string, bankToken: string): Promise<PayoutAccount> {
    return (await this.invoke<{ account: PayoutAccount }>("payout-account", { studio_id: studioId, account_holder: holder, bank_token: bankToken, action: "bank", client: "web" })).account;
  }

  /** Occupied periods (bookings + blocks) used to compute availability. */
  async busyIntervals(studioIds: string[], from: Date, to: Date): Promise<Record<string, Interval[]>> {
    if (!studioIds.length) return {};
    const rows = await this.rpc<{ studio_id: string; starts_at: string; ends_at: string }[]>("studio_busy_intervals", {
      p_studio_ids: studioIds, p_from: from.toISOString(), p_to: to.toISOString(),
    });
    const result: Record<string, Interval[]> = {};
    for (const r of rows ?? []) (result[r.studio_id] ??= []).push({ start: new Date(r.starts_at), end: new Date(Math.max(+new Date(r.starts_at), +new Date(r.ends_at))) });
    return result;
  }

  async blockedSlots(studioId: string): Promise<BlockedSlot[]> {
    return unwrap(await this.client.from("blocked_slots").select("*").eq("studio_id", studioId).gte("ends_at", new Date().toISOString()).order("starts_at"));
  }
  async addBlockedSlot(slot: BlockedSlot): Promise<BlockedSlot> {
    return unwrap(await this.client.from("blocked_slots").insert(slot).select().single());
  }
  async removeBlockedSlot(id: string) { unwrap(await this.client.from("blocked_slots").delete().eq("id", id)); }

  // MARK: Bookings
  // Booking actions run as database functions; steps that move card money use the Stripe edge functions.

  createBooking(studioId: string, sessionTypeId: string, startsAt: Date, hours: number, addOns: Record<string, number>, notes: string, promoCode?: string | null) {
    return this.rpc<Booking>("book_session", {
      p_studio_id: studioId, p_session_type_id: sessionTypeId, p_starts_at: startsAt.toISOString(), p_hours: hours,
      p_add_ons: addOnList(addOns), p_notes: notes, p_promo_code: promoCode || null,
    });
  }

  /** The exact price the booking will get (studio offers and promo code included). */
  quoteBooking(studioId: string, sessionTypeId: string, hours: number, addOns: Record<string, number>, promoCode?: string | null) {
    return this.rpc<PriceBreakdown>("quote_booking", {
      p_studio_id: studioId, p_session_type_id: sessionTypeId, p_hours: hours, p_add_ons: addOnList(addOns), p_promo_code: promoCode || null,
    });
  }

  checkPromoCode(studioId: string, code: string) {
    return this.rpc<PromoCheck>("check_promo_code", { p_studio_id: studioId, p_code: code });
  }

  /** Live banners from the EasySesh team (outages, announcements). */
  async siteBanners(): Promise<SiteBanner[]> {
    return unwrap(await this.client.from("site_banners").select("*").order("created_at", { ascending: false }).limit(10));
  }

  // MARK: Offers and promo codes (studio side)

  async studioOffers(studioId: string): Promise<StudioOffer[]> {
    return unwrap(await this.client.from("studio_offers").select("*").eq("studio_id", studioId).order("percent_off", { ascending: false }));
  }
  async saveOffer(offer: Omit<StudioOffer, "id" | "created_at"> & { id?: string }): Promise<StudioOffer> {
    const { id, ...row } = offer;
    if (id) return unwrap(await this.client.from("studio_offers").update(row).eq("id", id).select().single());
    return unwrap(await this.client.from("studio_offers").insert(row).select().single());
  }
  async removeOffer(id: string): Promise<void> {
    unwrap(await this.client.from("studio_offers").delete().eq("id", id));
  }
  async promoCodes(studioId: string): Promise<PromoCode[]> {
    const codes: PromoCode[] = unwrap(await this.client.from("promo_codes").select("*").eq("studio_id", studioId).order("created_at", { ascending: false }));
    const usage: { promo_code_id: string; uses: number }[] = unwrap(await this.client.from("promo_code_usage").select("*").in("promo_code_id", codes.map((c) => c.id)));
    return codes.map((c) => ({ ...c, uses: usage.find((u) => u.promo_code_id === c.id)?.uses ?? 0 }));
  }
  async savePromoCode(code: Partial<PromoCode> & { studio_id: string }): Promise<PromoCode> {
    const { id, uses: _u, created_at: _c, ...row } = code;
    if (id) return unwrap(await this.client.from("promo_codes").update(row).eq("id", id).select().single());
    return unwrap(await this.client.from("promo_codes").insert(row).select().single());
  }
  async removePromoCode(id: string): Promise<void> {
    unwrap(await this.client.from("promo_codes").delete().eq("id", id));
  }

  private async bookingAction(rpcName: string, params: Record<string, unknown>, edge: string, body: Record<string, unknown>): Promise<Booking> {
    try {
      return await this.rpc<Booking>(rpcName, params);
    } catch (error) {
      if (!(error instanceof AppError) || !error.message.includes("needs_payment_service")) throw error;
      return this.invoke<Booking>(edge, body);
    }
  }

  async preparePayment(bookingId: string): Promise<PaymentIntentInfo> {
    const r = await this.invoke<PaymentIntentInfo>("create-payment-intent", { booking_id: bookingId });
    return { ...r, currency: r.currency.toUpperCase() };
  }
  /** Idempotent: reads the PaymentIntent from Stripe and applies the same transition as the webhook. */
  confirmPayment = (bookingId: string) => this.invoke<Booking>("confirm-payment", { booking_id: bookingId });
  confirmCashBooking = (bookingId: string) => this.rpc<Booking>("confirm_cash_booking", { p_booking_id: bookingId });
  markCashReceived = (bookingId: string) => this.rpc<Booking>("mark_cash_received", { p_booking_id: bookingId });

  async booking(id: string): Promise<Booking> { return unwrap(await this.client.from("bookings").select("*").eq("id", id).single()); }

  async artistBookings(): Promise<Booking[]> {
    const id = await this.userId();
    return unwrap(await this.client.from("bookings").select("*").eq("artist_id", id).neq("status", "awaiting_payment").order("starts_at", { ascending: false }));
  }

  async studioBookings(studioId: string): Promise<Booking[]> {
    return unwrap(await this.client.from("bookings").select("*").eq("studio_id", studioId).neq("status", "awaiting_payment").order("starts_at", { ascending: false }));
  }

  cancelBooking = (id: string, reason: string) =>
    this.bookingAction("cancel_booking", { p_booking_id: id, p_reason: reason }, "cancel-booking", { booking_id: id, reason });
  rescheduleBooking = (id: string, start: Date) => this.rpc<Booking>("reschedule_booking", { p_booking_id: id, p_starts_at: start.toISOString() });
  respondToBooking = (id: string, accept: boolean, message: string | null) =>
    this.bookingAction("respond_booking", { p_booking_id: id, p_accept: accept, p_message: message }, "respond-booking", { booking_id: id, accept, message });
  checkIn = (id: string, lat: number | null, lng: number | null) => this.rpc<Booking>("check_in_booking", { p_booking_id: id, p_lat: lat, p_lng: lng });
  confirmArrival = (id: string) => this.rpc<Booking>("confirm_artist_arrival", { p_booking_id: id });
  openDispute = (id: string, reason: string) => this.rpc<void>("open_dispute", { p_booking_id: id, p_reason: reason });

  // MARK: Payments

  async transactions(bookingId: string): Promise<PaymentTransaction[]> {
    return unwrap(await this.client.from("transactions").select("*").eq("booking_id", bookingId).order("created_at"));
  }
  async feeLedger(studioId: string): Promise<FeeLedgerEntry[]> {
    return unwrap(await this.client.from("studio_fee_ledger").select("*").eq("studio_id", studioId).order("created_at", { ascending: false }));
  }
  async payouts(studioId: string): Promise<Payout[]> {
    return unwrap(await this.client.from("payouts").select("*").eq("studio_id", studioId).order("scheduled_for", { ascending: false }));
  }
  async feeInvoices(studioId: string): Promise<FeeInvoice[]> {
    return unwrap(await this.client.from("studio_fee_invoices").select("*").eq("studio_id", studioId).order("created_at", { ascending: false }));
  }

  // MARK: Chat

  async conversations(): Promise<Conversation[]> {
    return unwrap(await this.client.from("conversations").select("*").order("last_message_at", { ascending: false }));
  }
  async conversationById(id: string): Promise<Conversation> {
    return unwrap(await this.client.from("conversations").select("*").eq("id", id).single());
  }
  conversation = (studioId: string, bookingId: string | null) => this.rpc<Conversation>("get_or_create_conversation", { p_studio_id: studioId, p_booking_id: bookingId });

  async messages(conversationId: string): Promise<ChatMessage[]> {
    return unwrap(await this.client.from("messages").select("*").eq("conversation_id", conversationId).order("created_at").limit(500));
  }

  async sendMessage(conversationId: string, body: string): Promise<ChatMessage> {
    const sender_id = await this.userId();
    return unwrap(await this.client.from("messages").insert({ conversation_id: conversationId, sender_id, kind: "text", body: body.trim() }).select().single());
  }

  startConversation = (artistId: string, body: string) => this.rpc<Conversation>("studio_start_conversation", { p_artist_id: artistId, p_body: body });
  respondToMessageRequest = (id: string, accept: boolean) => this.rpc<Conversation>("respond_message_request", { p_conversation_id: id, p_accept: accept });
  /** Every artist an approved studio can browse; promoted ones first. Filtering happens on the device. */
  discoverArtists = () => this.rpc<DiscoveredArtist[]>("discover_artists", {});
  searchArtists = (query: string) => this.rpc<ArtistSearchResult[]>("search_artists", { p_query: query });
  markConversationRead = (id: string) => this.rpc<void>("mark_conversation_read", { p_conversation_id: id });

  /** Live new messages in a conversation. Returns a function that stops listening. */
  subscribeMessages(conversationId: string, onMessage: (m: ChatMessage) => void): () => void {
    const id = conversationId.toLowerCase();
    const channel: RealtimeChannel = this.client.channel(`messages-${id}-${uuid().slice(0, 8)}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `conversation_id=eq.${id}` },
        (payload) => onMessage(payload.new as ChatMessage))
      .subscribe();
    return () => { this.client.removeChannel(channel); };
  }

  /** Live inbox: any change to the user's notifications. */
  subscribeNotifications(userId: string, onChange: () => void): () => void {
    const channel = this.client.channel(`notifications-${userId}-${uuid().slice(0, 8)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "notifications", filter: `user_id=eq.${userId}` }, () => onChange())
      .subscribe();
    return () => { this.client.removeChannel(channel); };
  }

  // MARK: Promotions & links

  async promotions(studioId: string): Promise<StudioPromotion[]> {
    return unwrap(await this.client.from("studio_promotions").select("*").eq("studio_id", studioId).order("created_at", { ascending: false }));
  }
  // MARK: Stories

  storyFeed = () => this.rpc<StoryAuthor[]>("story_feed", {});
  userStories = (userId: string) => this.rpc<Story[]>("user_stories", { p_user_id: userId });
  storyActivity = (storyId: string) => this.rpc<StoryActivity[]>("story_activity", { p_story_id: storyId });
  async postStory(photo: Blob, caption: string): Promise<Story> {
    const url = await this.uploadImage(photo, "stories");
    return this.rpc<Story>("post_story", { p_media_url: url, p_caption: caption });
  }
  removeStory = (storyId: string) => this.rpc<void>("remove_story", { p_story_id: storyId });
  markStoryViewed = (storyId: string) => this.rpc<void>("mark_story_viewed", { p_story_id: storyId });
  likeStory = (storyId: string, like: boolean) => this.rpc<number>("like_story", { p_story_id: storyId, p_like: like });
  replyToStory = (storyId: string, body: string) => this.rpc<unknown>("reply_to_story", { p_story_id: storyId, p_body: body });

  async verificationRequests(userId: string): Promise<VerificationRequest[]> {
    return unwrap(await this.client.from("verification_requests").select("*").eq("user_id", userId).order("created_at", { ascending: false }).limit(10));
  }
  requestVerification = (message: string, links: string[]) => this.rpc<VerificationRequest>("request_verification", { p_message: message, p_links: links });
  cancelVerificationRequest = (id: string) => this.rpc<void>("cancel_verification_request", { p_request_id: id });
  async artistPromotions(artistId: string): Promise<StudioPromotion[]> {
    return unwrap(await this.client.from("studio_promotions").select("*").eq("artist_id", artistId).order("created_at", { ascending: false }));
  }
  /** Orders a promotion for the caller's studio, or their artist profile; paid with promotionPayment. */
  requestPromotion = (pkg: string) => this.rpc<StudioPromotion>("request_promotion", { p_package: pkg });
  cancelPromotionRequest = (promotionId: string) => this.rpc<void>("cancel_promotion_request", { p_promotion_id: promotionId });
  promotionPayment = (promotionId: string) => this.invoke<{ client_secret: string; amount: number; currency: string }>("promotion-payment", { promotion_id: promotionId });
  confirmPromotion = (promotionId: string) => this.invoke<{ status: string }>("promotion-payment", { promotion_id: promotionId, confirm: true });
  /** The artist profiles a studio shows (a studio can have several owners); pending ones only for its owner. */
  async studioArtistLinks(studioId: string): Promise<StudioArtistLink[]> {
    return unwrap(await this.client.from("studio_artist_links").select("*").eq("studio_id", studioId).order("created_at"));
  }
  async artistStudioLinks(artistId: string): Promise<StudioArtistLink[]> {
    return unwrap(await this.client.from("studio_artist_links").select("*").eq("artist_id", artistId));
  }
  requestStudioArtistLink = (artistId: string) => this.rpc<StudioArtistLink>("request_studio_artist_link", { p_artist_id: artistId });
  respondStudioArtistLink = (studioId: string, accept: boolean) => this.rpc<void>("respond_studio_artist_link", { p_studio_id: studioId, p_accept: accept });
  removeStudioArtistLink = (studioId: string, artistId: string) => this.rpc<void>("remove_studio_artist_link", { p_studio_id: studioId, p_artist_id: artistId });

  // MARK: Artist ratings

  reviewArtist = (bookingId: string, rating: number, text: string) => this.rpc<ArtistReview>("review_artist", { p_booking_id: bookingId, p_rating: rating, p_text: text });
  async artistReviews(artistId: string): Promise<ArtistReview[]> {
    return unwrap(await this.client.from("artist_reviews").select("*").eq("artist_id", artistId).order("created_at", { ascending: false }).limit(50));
  }
  async artistReview(bookingId: string): Promise<ArtistReview | null> {
    return unwrap(await this.client.from("artist_reviews").select("*").eq("booking_id", bookingId).limit(1).maybeSingle());
  }

  // MARK: Blocking

  conversationBlockState = (id: string) => this.rpc<BlockState>("conversation_block_state", { p_conversation_id: id });
  setConversationBlock = (id: string, blocked: boolean) => this.rpc<BlockState>("set_conversation_block", { p_conversation_id: id, p_blocked: blocked });
  blockUser = (id: string) => this.rpc<void>("block_user", { p_user_id: id });
  blockStudio = (id: string) => this.rpc<void>("block_studio", { p_studio_id: id });
  unblockUser = (id: string) => this.rpc<void>("unblock_user", { p_user_id: id });
  blockedUsers = () => this.rpc<BlockedUser[]>("my_blocked_users");

  // MARK: Disputes, moderation, changelog

  disputeRating = (kind: "studio_review" | "artist_review", reviewId: string, reason: string) =>
    this.rpc<void>("dispute_rating", { p_review_type: kind, p_review_id: reviewId, p_reason: reason });

  /** Warnings, suspensions and account changes by the team, newest first (kept even when notifications are deleted). */
  async accountHistory(): Promise<{ moderation: ModerationRecord[]; changes: AccountChangeNotice[] }> {
    const id = await this.userId();
    const [moderation, changes] = await Promise.all([
      this.client.from("moderation_actions").select("id, action, reason, ends_at, created_at, studio_id").eq("user_id", id).order("created_at", { ascending: false }).limit(200),
      this.client.from("account_change_notices").select("id, changes, reason, created_at").eq("user_id", id).order("created_at", { ascending: false }).limit(200),
    ]);
    return { moderation: unwrap(moderation), changes: unwrap(changes) };
  }

  async unacknowledgedWarnings(): Promise<ModerationWarning[]> {
    const rows: ModerationWarning[] = unwrap(await this.client.from("moderation_actions").select("id, reason, created_at, acknowledged_at")
      .eq("action", "warning").order("created_at").limit(50));
    return rows.filter((w) => !w.acknowledged_at);
  }
  acknowledgeWarning = (id: string) => this.rpc<void>("acknowledge_warning", { p_id: id });
  async changelog(): Promise<ChangelogEntry[]> {
    return unwrap(await this.client.from("app_changelog").select("*").order("published_at", { ascending: false }).limit(30));
  }
  currentTermsVersion = () => this.rpc<string>("current_terms_version");

  // MARK: Support

  async supportTickets(): Promise<SupportTicket[]> {
    return unwrap(await this.client.from("support_tickets").select("*").order("last_message_at", { ascending: false }));
  }
  async supportTicket(id: string): Promise<SupportTicket> {
    return unwrap(await this.client.from("support_tickets").select("*").eq("id", id).single());
  }
  createSupportTicket = (subject: string, category: SupportCategory, body: string, bookingId: string | null) =>
    this.rpc<SupportTicket>("create_support_ticket", { p_subject: subject.trim(), p_category: category, p_body: body, p_booking_id: bookingId });
  async supportMessages(ticketId: string): Promise<SupportMessage[]> {
    return unwrap(await this.client.from("support_messages").select("*").eq("ticket_id", ticketId).order("created_at"));
  }
  sendSupportMessage = (ticketId: string, body: string) => this.rpc<SupportMessage>("send_support_message", { p_ticket_id: ticketId, p_body: body });
  markSupportTicketRead = (id: string) => this.rpc<void>("mark_support_ticket_read", { p_ticket_id: id });
  rateSupportTicket = (id: string, rating: number, comment: string) => this.rpc<SupportTicket>("rate_support_ticket", { p_ticket_id: id, p_rating: rating, p_comment: comment });
  closeSupportTicket = (id: string) => this.rpc<SupportTicket>("set_support_ticket_status", { p_ticket_id: id, p_status: "closed" });

  // MARK: Reviews & reports

  async reviews(studioId: string): Promise<Review[]> {
    return unwrap(await this.client.from("reviews").select("*").eq("studio_id", studioId).eq("is_hidden", false).order("created_at", { ascending: false }));
  }

  async submitReview(review: Omit<Review, "id" | "created_at" | "artist_id">): Promise<Review> {
    const artist_id = await this.userId();
    const { studio_reply: _r, studio_replied_at: _d, ...row } = review as Review;
    return unwrap(await this.client.from("reviews").insert({ ...row, artist_id }).select().single());
  }
  replyToReview = (id: string, reply: string) => this.rpc<Review>("reply_to_review", { p_review_id: id, p_reply: reply });

  async report(target: ReportTarget, targetId: string, reason: ReportReason, details: string) {
    const reporter_id = await this.userId();
    unwrap(await this.client.from("reports").insert({ reporter_id, target_type: target, target_id: targetId, reason, details }));
  }

  // MARK: Notifications

  async notifications(): Promise<AppNotification[]> {
    return unwrap(await this.client.from("notifications").select("*").order("created_at", { ascending: false }).limit(100));
  }
  async markNotificationRead(id: string) { unwrap(await this.client.from("notifications").update({ is_read: true }).eq("id", id)); }
  async markAllNotificationsRead() {
    const id = await this.userId();
    unwrap(await this.client.from("notifications").update({ is_read: true }).eq("user_id", id).eq("is_read", false));
  }
  async deleteNotification(id: string) { unwrap(await this.client.from("notifications").delete().eq("id", id)); }
  async deleteAllNotifications() {
    const id = await this.userId();
    unwrap(await this.client.from("notifications").delete().eq("user_id", id));
  }
}

export const api = new Api();
