import Foundation
import Supabase

/// Production backend: Supabase Auth, Postgres (with row-level security), Storage, Realtime and
/// Edge Functions (for anything that moves money – see `supabase/functions`).
@MainActor
final class SupabaseBackend: Backend {
    private let client: SupabaseClient
    private let decoder = PostgresCoding.decoder()

    init() {
        let encoder = PostgresCoding.encoder()

        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL ?? URL(string: "https://invalid.supabase.co")!,
            supabaseKey: AppConfig.supabaseAnonKey ?? "",
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: PostgresCoding.decoder()),
                auth: .init(redirectToURL: AppConfig.redirectURL)
            )
        )
    }

    func handle(url: URL) {
        client.auth.handle(url)
    }

    /// Completes a sign-in link (email confirmation, magic link or password reset).
    /// Returns true when the link was a password reset, so the app can ask for a new password.
    func completeAuthLink(_ url: URL) async throws -> Bool {
        _ = try await mapped { try await client.auth.session(from: url) }
        let text = url.absoluteString
        return text.contains("type=recovery")
    }

    // MARK: - Helpers

    private func userId() throws -> UUID {
        guard let id = client.auth.currentUser?.id else { throw BackendError.notAuthenticated }
        return id
    }

    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as BackendError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as PostgrestError {
            throw Self.map(message: error.message, code: error.code)
        } catch let error as AuthError {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("invalid login") { throw BackendError.invalidCredentials }
            if message.localizedCaseInsensitiveContains("already registered") { throw BackendError.emailInUse }
            throw BackendError.server(message)
        } catch let FunctionsError.httpError(_, data) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Request failed."
            throw Self.map(message: message, code: nil)
        } catch {
            throw BackendError.server(error.localizedDescription)
        }
    }

    private static func map(message: String, code: String?) -> BackendError {
        switch message {
        case "slot_unavailable": return .slotUnavailable
        case "forbidden": return .forbidden
        case "not_found": return .notFound
        case "account_suspended": return .accountSuspended
        default:
            // Raised with `raise exception using errcode = 'P0001'` → user-facing message.
            if code == "23P01" { return .slotUnavailable }
            if code == "42501" { return .forbidden }
            return .validation(message)
        }
    }

    private func invoke<T: Decodable>(_ function: String, _ body: [String: AnyJSON]) async throws -> T {
        try await mapped {
            try await client.functions.invoke(function, options: FunctionInvokeOptions(body: body), decoder: decoder)
        }
    }

    private func rpc<T: Decodable>(_ function: String, _ params: [String: AnyJSON] = [:]) async throws -> T {
        try await mapped {
            try await client.rpc(function, params: params).execute().value
        }
    }

    private func rpcVoid(_ function: String, _ params: [String: AnyJSON]) async throws {
        try await mapped { _ = try await client.rpc(function, params: params).execute() }
    }

    private func account(id: UUID) async throws -> UserAccount {
        try await mapped {
            try await client.from("profiles").select().eq("id", value: id.uuidString).single().execute().value
        }
    }

    private func ensureActive(_ account: UserAccount) async throws -> UserAccount {
        var account = account
        // A suspension whose period is over is lifted right away instead of waiting for the job.
        if account.status != .active, let until = account.statusUntil, until <= .now,
           let lifted: UserAccount = try? await rpc("lift_my_expired_restriction") {
            account = lifted
        }
        guard account.status == .active else {
            try? await client.auth.signOut()
            throw BackendError.accountRestricted(banned: account.status == .banned, until: account.statusUntil, reason: account.statusReason)
        }
        return account
    }

    // MARK: - Auth

    func restoreSession() async -> UserAccount? {
        guard let session = try? await client.auth.session else { return nil }
        return try? await ensureActive(account(id: session.user.id))
    }

    func signUp(email: String, password: String, role: UserRole) async throws -> UserAccount {
        if let problem = PasswordPolicy.problem(password) { throw BackendError.validation(problem) }
        // The sign-up form requires accepting the terms; the version is stored as the consent record.
        let response = try await mapped {
            try await client.auth.signUp(
                email: email,
                password: password,
                data: ["role": .string(role.rawValue), "terms_version": .string(LegalDocument.currentVersion)],
                redirectTo: AppConfig.redirectURL
            )
        }
        guard response.session != nil else {
            throw BackendError.validation("We sent you a confirmation email. Open the link, then sign in.")
        }
        return try await account(id: response.user.id)
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        let session = try await mapped { try await client.auth.signIn(email: email, password: password) }
        return try await ensureActive(account(id: session.user.id))
    }

    func signInWithApple(idToken: String, nonce: String, role: UserRole) async throws -> UserAccount {
        let session = try await mapped {
            try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        }
        return try await finishSocialSignIn(userId: session.user.id, role: role)
    }

    func signInWithGoogle(role: UserRole) async throws -> UserAccount {
        let session = try await mapped {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: AppConfig.redirectURL)
        }
        return try await finishSocialSignIn(userId: session.user.id, role: role)
    }

    /// Social sign-up creates an artist by default; brand-new accounts may switch to studio owner once.
    private func finishSocialSignIn(userId: UUID, role: UserRole) async throws -> UserAccount {
        if role == .studioOwner {
            try? await rpcVoid("claim_role", ["p_role": .string(role.rawValue)])
        }
        return try await ensureActive(account(id: userId))
    }

    func sendPasswordReset(email: String) async throws {
        try await mapped { try await client.auth.resetPasswordForEmail(email, redirectTo: AppConfig.redirectURL) }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func changePassword(to newPassword: String) async throws {
        if let problem = PasswordPolicy.problem(newPassword) { throw BackendError.validation(problem) }
        _ = try await mapped { try await client.auth.update(user: UserAttributes(password: newPassword)) }
    }

    func deleteAccount() async throws {
        let _: [String: Bool] = try await invoke("delete-account", [:])
        try? await client.auth.signOut()
    }

    func acceptTerms(version: String) async throws -> UserAccount {
        try await rpc("accept_terms", ["p_version": .string(version)])
    }

    func exportPersonalData() async throws -> Data {
        let json: AnyJSON = try await mapped {
            try await client.functions.invoke("export-data", options: FunctionInvokeOptions(body: [String: AnyJSON]()), decoder: JSONDecoder())
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(json)
    }

    func updateSettings(_ settings: UserSettings) async throws -> UserAccount {
        let id = try userId()
        struct Patch: Encodable { let settings: UserSettings }
        return try await mapped {
            try await client.from("profiles").update(Patch(settings: settings)).eq("id", value: id.uuidString).select().single().execute().value
        }
    }

    // MARK: - Profiles

    func artistProfile(id: UUID) async throws -> ArtistProfile? {
        let rows: [ArtistProfile] = try await mapped {
            try await client.from("artist_profiles").select().eq("id", value: id.uuidString).limit(1).execute().value
        }
        return rows.first
    }

    func saveArtistProfile(_ profile: ArtistProfile) async throws -> ArtistProfile {
        try await mapped {
            try await client.from("artist_profiles").upsert(profile).select().single().execute().value
        }
    }

    func uploadImage(_ data: Data, folder: String) async throws -> String {
        let id = try userId()
        // Storage policies only allow writes under the caller's own user-id prefix.
        let path = "\(id.uuidString.lowercased())/\(folder)/\(UUID().uuidString.lowercased()).jpg"
        return try await mapped {
            _ = try await client.storage.from("media").upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return try client.storage.from("media").getPublicURL(path: path).absoluteString
        }
    }

    // MARK: - Studios

    func publishedStudios() async throws -> [Studio] {
        try await mapped {
            try await client.from("studios").select()
                .eq("status", value: StudioStatus.approved.rawValue)
                .eq("is_active", value: true)
                .order("name")
                .execute().value
        }
    }

    func studio(id: UUID) async throws -> Studio {
        try await mapped {
            try await client.from("studios").select().eq("id", value: id.uuidString).single().execute().value
        }
    }

    func ownedStudio() async throws -> Studio? {
        let id = try userId()
        let rows: [Studio] = try await mapped {
            try await client.from("studios").select().eq("owner_id", value: id.uuidString).limit(1).execute().value
        }
        return rows.first
    }

    func saveStudio(_ studio: Studio) async throws -> Studio {
        // Moderation columns are protected by a trigger; the owner can only change listing content.
        try await mapped {
            try await client.from("studios").upsert(studio.normalized()).select().single().execute().value
        }
    }

    func submitStudioForReview(id: UUID) async throws -> Studio {
        try await rpc("submit_studio_for_review", ["p_studio_id": .string(id.uuidString)])
    }

    func setStudioActive(id: UUID, isActive: Bool) async throws -> Studio {
        try await rpc("set_studio_active", ["p_studio_id": .string(id.uuidString), "p_active": .bool(isActive)])
    }

    func payoutAccount(studioId: UUID) async throws -> PayoutAccount? {
        let rows: [PayoutAccount] = try await mapped {
            try await client.from("studio_payout_accounts").select().eq("studio_id", value: studioId.uuidString).limit(1).execute().value
        }
        return rows.first
    }

    private struct PayoutAccountResponse: Decodable {
        let account: PayoutAccount
        let onboardingUrl: String?
    }

    func savePayoutAccount(_ account: PayoutAccount, iban: String?) async throws -> PayoutAccount {
        // Bank details are collected by Stripe's hosted onboarding, never sent through our servers.
        let response: PayoutAccountResponse = try await invoke("payout-account", [
            "studio_id": .string(account.studioId.uuidString),
            "account_holder": .string(account.accountHolder),
            "action": .string("save"),
        ])
        return response.account
    }

    func payoutOnboardingURL(studioId: UUID) async throws -> URL? {
        let response: PayoutAccountResponse = try await invoke("payout-account", [
            "studio_id": .string(studioId.uuidString),
            "action": .string("onboarding_link"),
        ])
        return response.onboardingUrl.flatMap(URL.init(string:))
    }

    func busyIntervals(studioIds: [UUID], from: Date, to: Date) async throws -> [UUID: [DateInterval]] {
        struct Row: Decodable { let studioId: UUID; let startsAt: Date; let endsAt: Date }
        let rows: [Row] = try await rpc("studio_busy_intervals", [
            "p_studio_ids": .array(studioIds.map { .string($0.uuidString) }),
            "p_from": .string(PostgresDate.format(from)),
            "p_to": .string(PostgresDate.format(to)),
        ])
        return Dictionary(grouping: rows, by: \.studioId).mapValues { $0.map { DateInterval(start: $0.startsAt, end: max($0.startsAt, $0.endsAt)) } }
    }

    func blockedSlots(studioId: UUID) async throws -> [BlockedSlot] {
        try await mapped {
            try await client.from("blocked_slots").select().eq("studio_id", value: studioId.uuidString).gte("ends_at", value: PostgresDate.format(.now)).order("starts_at").execute().value
        }
    }

    func addBlockedSlot(_ slot: BlockedSlot) async throws -> BlockedSlot {
        try await mapped {
            try await client.from("blocked_slots").insert(slot).select().single().execute().value
        }
    }

    func removeBlockedSlot(id: UUID) async throws {
        try await mapped { _ = try await client.from("blocked_slots").delete().eq("id", value: id.uuidString).execute() }
    }

    // MARK: - Bookings

    // Booking actions run as database functions (no edge functions needed). Only steps that move
    // card money (charging, capturing, refunding) go through the Stripe edge functions.
    func createBooking(_ request: BookingRequest) async throws -> Booking {
        try await rpc("create_booking", [
            "p_studio_id": .string(request.studio.id.uuidString),
            "p_session_type_id": .string(request.sessionType.id),
            "p_starts_at": .string(PostgresDate.format(request.startsAt)),
            "p_hours": .integer(request.hours),
            "p_add_ons": .array(request.addOns.filter { $0.value > 0 }.map { AnyJSON.object(["id": .string($0.key), "quantity": .integer($0.value)]) }),
            "p_notes": .string(request.notes),
        ])
    }

    /// Runs the database version first; card bookings that need a refund/capture use the edge function.
    private func bookingAction(_ rpcName: String, _ params: [String: AnyJSON], edge: String, _ edgeBody: [String: AnyJSON]) async throws -> Booking {
        do {
            return try await rpc(rpcName, params)
        } catch BackendError.validation(let message) where message == "needs_payment_service" {
            return try await invoke(edge, edgeBody)
        }
    }

    func preparePayment(bookingId: UUID, method: PaymentMethod) async throws -> PaymentIntentInfo {
        struct Response: Decodable {
            let clientSecret: String
            let customerId: String?
            let ephemeralKey: String?
            let amount: Int
            let currency: String
            let captureLater: Bool
        }
        let response: Response = try await invoke("create-payment-intent", ["booking_id": .string(bookingId.uuidString)])
        return PaymentIntentInfo(bookingId: bookingId, clientSecret: response.clientSecret, customerId: response.customerId, ephemeralKey: response.ephemeralKey, amount: response.amount, currency: response.currency.uppercased(), captureLater: response.captureLater)
    }

    func confirmPayment(bookingId: UUID, method: PaymentMethod) async throws -> Booking {
        // Idempotent: reads the PaymentIntent from Stripe and applies the same transition as the webhook.
        try await invoke("confirm-payment", ["booking_id": .string(bookingId.uuidString)])
    }

    func confirmCashBooking(bookingId: UUID) async throws -> Booking {
        try await rpc("confirm_cash_booking", ["p_booking_id": .string(bookingId.uuidString)])
    }

    func markCashReceived(bookingId: UUID) async throws -> Booking {
        try await rpc("mark_cash_received", ["p_booking_id": .string(bookingId.uuidString)])
    }

    func booking(id: UUID) async throws -> Booking {
        try await mapped {
            try await client.from("bookings").select().eq("id", value: id.uuidString).single().execute().value
        }
    }

    func artistBookings() async throws -> [Booking] {
        let id = try userId()
        return try await mapped {
            try await client.from("bookings").select()
                .eq("artist_id", value: id.uuidString)
                .neq("status", value: BookingStatus.awaitingPayment.rawValue)
                .order("starts_at", ascending: false)
                .execute().value
        }
    }

    func studioBookings(studioId: UUID) async throws -> [Booking] {
        try await mapped {
            try await client.from("bookings").select()
                .eq("studio_id", value: studioId.uuidString)
                .neq("status", value: BookingStatus.awaitingPayment.rawValue)
                .order("starts_at", ascending: false)
                .execute().value
        }
    }

    func cancelBooking(id: UUID, reason: String) async throws -> Booking {
        try await bookingAction("cancel_booking", ["p_booking_id": .string(id.uuidString), "p_reason": .string(reason)],
                                edge: "cancel-booking", ["booking_id": .string(id.uuidString), "reason": .string(reason)])
    }

    func rescheduleBooking(id: UUID, newStart: Date) async throws -> Booking {
        try await rpc("reschedule_booking", ["p_booking_id": .string(id.uuidString), "p_starts_at": .string(PostgresDate.format(newStart))])
    }

    func respondToBooking(id: UUID, accept: Bool, message: String?) async throws -> Booking {
        let text = message.map { AnyJSON.string($0) } ?? AnyJSON.null
        return try await bookingAction("respond_booking", ["p_booking_id": .string(id.uuidString), "p_accept": .bool(accept), "p_message": text],
                                       edge: "respond-booking", ["booking_id": .string(id.uuidString), "accept": .bool(accept), "message": text])
    }

    func checkIn(bookingId: UUID, latitude: Double?, longitude: Double?) async throws -> Booking {
        try await rpc("check_in_booking", [
            "p_booking_id": .string(bookingId.uuidString),
            "p_lat": latitude.map { AnyJSON.double($0) } ?? .null,
            "p_lng": longitude.map { AnyJSON.double($0) } ?? .null,
        ])
    }

    func confirmArrival(bookingId: UUID) async throws -> Booking {
        try await rpc("confirm_artist_arrival", ["p_booking_id": .string(bookingId.uuidString)])
    }

    func openDispute(bookingId: UUID, reason: String) async throws {
        try await rpcVoid("open_dispute", ["p_booking_id": .string(bookingId.uuidString), "p_reason": .string(reason)])
    }

    // MARK: - Payments

    func transactions(bookingId: UUID) async throws -> [PaymentTransaction] {
        try await mapped {
            try await client.from("transactions").select().eq("booking_id", value: bookingId.uuidString).order("created_at").execute().value
        }
    }

    func feeLedger(studioId: UUID) async throws -> [FeeLedgerEntry] {
        try await mapped {
            try await client.from("studio_fee_ledger").select().eq("studio_id", value: studioId.uuidString).order("created_at", ascending: false).execute().value
        }
    }

    func payouts(studioId: UUID) async throws -> [Payout] {
        try await mapped {
            try await client.from("payouts").select().eq("studio_id", value: studioId.uuidString).order("scheduled_for", ascending: false).execute().value
        }
    }

    // MARK: - Chat

    func conversations() async throws -> [Conversation] {
        try await mapped {
            try await client.from("conversations").select().order("last_message_at", ascending: false).execute().value
        }
    }

    func conversation(studioId: UUID, bookingId: UUID?) async throws -> Conversation {
        try await rpc("get_or_create_conversation", [
            "p_studio_id": .string(studioId.uuidString),
            "p_booking_id": bookingId.map { AnyJSON.string($0.uuidString) } ?? AnyJSON.null,
        ])
    }

    func messages(conversationId: UUID) async throws -> [ChatMessage] {
        try await mapped {
            try await client.from("messages").select().eq("conversation_id", value: conversationId.uuidString).order("created_at").limit(500).execute().value
        }
    }

    func sendMessage(conversationId: UUID, body: String) async throws -> ChatMessage {
        struct NewMessage: Encodable {
            let conversationId: UUID
            let senderId: UUID
            let kind: MessageKind
            let body: String
        }
        let message = NewMessage(conversationId: conversationId, senderId: try userId(), kind: .text, body: body.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await mapped {
            try await client.from("messages").insert(message).select().single().execute().value
        }
    }

    func startConversation(artistId: UUID, body: String) async throws -> Conversation {
        try await rpc("studio_start_conversation", ["p_artist_id": .string(artistId.uuidString), "p_body": .string(body)])
    }

    func respondToMessageRequest(conversationId: UUID, accept: Bool) async throws -> Conversation {
        try await rpc("respond_message_request", ["p_conversation_id": .string(conversationId.uuidString), "p_accept": .bool(accept)])
    }

    func searchArtists(query: String) async throws -> [ArtistSearchResult] {
        try await rpc("search_artists", ["p_query": .string(query)])
    }

    // MARK: Promotions

    func promotions(studioId: UUID) async throws -> [StudioPromotion] {
        try await mapped {
            try await client.from("studio_promotions").select().eq("studio_id", value: studioId.uuidString)
                .order("created_at", ascending: false).execute().value
        }
    }

    func requestPromotion(_ package: PromotionPackage) async throws -> StudioPromotion {
        try await rpc("request_promotion", ["p_package": .string(package.rawValue)])
    }

    func cancelPromotionRequest(id: UUID) async throws {
        try await rpcVoid("cancel_promotion_request", ["p_promotion_id": .string(id.uuidString)])
    }

    func preparePromotionPayment(promotionId: UUID) async throws -> PaymentIntentInfo {
        struct Response: Decodable {
            let clientSecret: String
            let customerId: String?
            let ephemeralKey: String?
            let amount: Int
            let currency: String
        }
        let response: Response = try await invoke("promotion-payment", ["promotion_id": .string(promotionId.uuidString)])
        return PaymentIntentInfo(bookingId: promotionId, clientSecret: response.clientSecret, customerId: response.customerId,
                                 ephemeralKey: response.ephemeralKey, amount: response.amount, currency: response.currency.uppercased(), captureLater: false)
    }

    func confirmPromotionPayment(promotionId: UUID) async throws {
        struct Response: Decodable { let status: String }
        let _: Response = try await invoke("promotion-payment", ["promotion_id": .string(promotionId.uuidString), "confirm": .bool(true)])
    }

    // MARK: Artist ratings

    func reviewArtist(bookingId: UUID, rating: Int, text: String) async throws -> ArtistReview {
        try await rpc("review_artist", ["p_booking_id": .string(bookingId.uuidString), "p_rating": .integer(rating), "p_text": .string(text)])
    }

    func artistReviews(artistId: UUID) async throws -> [ArtistReview] {
        try await mapped {
            try await client.from("artist_reviews").select().eq("artist_id", value: artistId.uuidString)
                .order("created_at", ascending: false).limit(50).execute().value
        }
    }

    func artistReview(bookingId: UUID) async throws -> ArtistReview? {
        let rows: [ArtistReview] = try await mapped {
            try await client.from("artist_reviews").select().eq("booking_id", value: bookingId.uuidString).limit(1).execute().value
        }
        return rows.first
    }

    // MARK: Studio ↔ artist profile

    func studioArtistLink(studioId: UUID) async throws -> StudioArtistLink? {
        let rows: [StudioArtistLink] = try await mapped {
            try await client.from("studio_artist_links").select().eq("studio_id", value: studioId.uuidString).limit(1).execute().value
        }
        return rows.first
    }

    func artistStudioLinks(artistId: UUID) async throws -> [StudioArtistLink] {
        try await mapped {
            try await client.from("studio_artist_links").select().eq("artist_id", value: artistId.uuidString).execute().value
        }
    }

    func requestStudioArtistLink(artistId: UUID) async throws -> StudioArtistLink {
        try await rpc("request_studio_artist_link", ["p_artist_id": .string(artistId.uuidString)])
    }

    func respondStudioArtistLink(studioId: UUID, accept: Bool) async throws {
        try await rpcVoid("respond_studio_artist_link", ["p_studio_id": .string(studioId.uuidString), "p_accept": .bool(accept)])
    }

    func removeStudioArtistLink(studioId: UUID) async throws {
        try await rpcVoid("remove_studio_artist_link", ["p_studio_id": .string(studioId.uuidString)])
    }

    // MARK: Rating disputes & fee invoices

    func disputeRating(kind: RatingKind, reviewId: UUID, reason: String) async throws {
        try await rpcVoid("dispute_rating", ["p_review_type": .string(kind.rawValue), "p_review_id": .string(reviewId.uuidString), "p_reason": .string(reason)])
    }

    func unacknowledgedWarnings() async throws -> [ModerationWarning] {
        let all: [ModerationWarning] = try await mapped {
            try await client.from("moderation_actions").select("id, reason, created_at, acknowledged_at")
                .eq("action", value: "warning")
                .order("created_at", ascending: true).limit(50).execute().value
        }
        return all.filter { $0.acknowledgedAt == nil }
    }

    func acknowledgeWarning(id: UUID) async throws {
        try await rpcVoid("acknowledge_warning", ["p_id": .string(id.uuidString)])
    }

    func changelog() async throws -> [ChangelogEntry] {
        try await mapped {
            try await client.from("app_changelog").select().order("published_at", ascending: false).limit(30).execute().value
        }
    }

    func currentTermsVersion() async throws -> String {
        try await rpc("current_terms_version", [:])
    }

    func feeInvoices(studioId: UUID) async throws -> [FeeInvoice] {
        try await mapped {
            try await client.from("studio_fee_invoices").select().eq("studio_id", value: studioId.uuidString)
                .order("created_at", ascending: false).execute().value
        }
    }

    // MARK: Notification deletion

    func deleteNotification(id: UUID) async throws {
        try await mapped { _ = try await client.from("notifications").delete().eq("id", value: id.uuidString).execute() }
    }

    func deleteAllNotifications() async throws {
        let id = try userId()
        try await mapped { _ = try await client.from("notifications").delete().eq("user_id", value: id.uuidString).execute() }
    }

    // MARK: Support

    func supportTickets() async throws -> [SupportTicket] {
        try await mapped {
            try await client.from("support_tickets").select().order("last_message_at", ascending: false).execute().value
        }
    }

    func createSupportTicket(subject: String, category: SupportCategory, body: String, bookingId: UUID?) async throws -> SupportTicket {
        try await rpc("create_support_ticket", [
            "p_subject": .string(subject.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_category": .string(category.rawValue),
            "p_body": .string(body),
            "p_booking_id": bookingId.map { AnyJSON.string($0.uuidString) } ?? AnyJSON.null,
        ])
    }

    func supportMessages(ticketId: UUID) async throws -> [SupportMessage] {
        try await mapped {
            try await client.from("support_messages").select().eq("ticket_id", value: ticketId.uuidString).order("created_at").execute().value
        }
    }

    func sendSupportMessage(ticketId: UUID, body: String) async throws -> SupportMessage {
        try await rpc("send_support_message", ["p_ticket_id": .string(ticketId.uuidString), "p_body": .string(body)])
    }

    func markSupportTicketRead(id: UUID) async throws {
        try await rpcVoid("mark_support_ticket_read", ["p_ticket_id": .string(id.uuidString)])
    }

    func rateSupportTicket(id: UUID, rating: Int, comment: String) async throws -> SupportTicket {
        try await rpc("rate_support_ticket", [
            "p_ticket_id": .string(id.uuidString),
            "p_rating": .integer(rating),
            "p_comment": .string(comment),
        ])
    }

    func closeSupportTicket(id: UUID) async throws -> SupportTicket {
        try await rpc("set_support_ticket_status", ["p_ticket_id": .string(id.uuidString), "p_status": .string("closed")])
    }

    func markConversationRead(id: UUID) async throws {
        try await rpcVoid("mark_conversation_read", ["p_conversation_id": .string(id.uuidString)])
    }

    func messageStream(conversationId: UUID) -> AsyncStream<ChatMessage> {
        let client = client
        let decoder = decoder
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let channel = client.channel("messages-\(conversationId.uuidString.lowercased())")
                let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: "conversation_id=eq.\(conversationId.uuidString.lowercased())")
                await channel.subscribe()
                for await insert in inserts {
                    if let message = try? insert.decodeRecord(as: ChatMessage.self, decoder: decoder) {
                        continuation.yield(message)
                    }
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Reviews & moderation

    func reviews(studioId: UUID) async throws -> [Review] {
        try await mapped {
            try await client.from("reviews").select().eq("studio_id", value: studioId.uuidString).eq("is_hidden", value: false).order("created_at", ascending: false).execute().value
        }
    }

    func submitReview(_ review: Review) async throws -> Review {
        struct NewReview: Encodable {
            let bookingId: UUID
            let studioId: UUID
            let artistId: UUID
            let artistName: String
            let rating: Int
            let facilitiesRating: Int
            let experienceRating: Int
            let engineerRating: Int?
            let text: String
        }
        let row = NewReview(bookingId: review.bookingId, studioId: review.studioId, artistId: try userId(), artistName: review.artistName, rating: review.rating, facilitiesRating: review.facilitiesRating, experienceRating: review.experienceRating, engineerRating: review.engineerRating, text: review.text)
        return try await mapped {
            try await client.from("reviews").insert(row).select().single().execute().value
        }
    }

    func replyToReview(id: UUID, reply: String) async throws -> Review {
        try await rpc("reply_to_review", ["p_review_id": .string(id.uuidString), "p_reply": .string(reply)])
    }

    func report(target: ReportTarget, targetId: UUID, reason: ReportReason, details: String) async throws {
        struct NewReport: Encodable {
            let reporterId: UUID
            let targetType: ReportTarget
            let targetId: UUID
            let reason: ReportReason
            let details: String
        }
        let row = NewReport(reporterId: try userId(), targetType: target, targetId: targetId, reason: reason, details: details)
        try await mapped { _ = try await client.from("reports").insert(row).execute() }
    }

    // MARK: - Notifications

    func notifications() async throws -> [AppNotification] {
        try await mapped {
            try await client.from("notifications").select().order("created_at", ascending: false).limit(100).execute().value
        }
    }

    func markNotificationRead(id: UUID) async throws {
        struct Patch: Encodable { let isRead = true }
        try await mapped { _ = try await client.from("notifications").update(Patch()).eq("id", value: id.uuidString).execute() }
    }

    func markAllNotificationsRead() async throws {
        struct Patch: Encodable { let isRead = true }
        let id = try userId()
        try await mapped { _ = try await client.from("notifications").update(Patch()).eq("user_id", value: id.uuidString).eq("is_read", value: false).execute() }
    }

    func registerPushToken(_ token: String) async throws {
        struct Token: Encodable { let token: String; let userId: UUID; let platform: String }
        let row = Token(token: token, userId: try userId(), platform: "ios")
        try await mapped { _ = try await client.from("device_tokens").upsert(row, onConflict: "token").execute() }
    }
}
