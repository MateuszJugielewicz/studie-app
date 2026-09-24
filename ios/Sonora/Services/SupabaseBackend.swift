import Foundation
import Supabase

/// Production backend: Supabase Auth, Postgres (with row-level security), Storage, Realtime and
/// Edge Functions (for anything that moves money – see `supabase/functions`).
@MainActor
final class SupabaseBackend: Backend {
    let isDemo = false

    private let client: SupabaseClient
    private let decoder = SupabaseBackend.makeDecoder()

    init() {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL ?? URL(string: "https://invalid.supabase.co")!,
            supabaseKey: AppConfig.supabaseAnonKey ?? "",
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: SupabaseBackend.makeDecoder()),
                auth: .init(redirectToURL: AppConfig.redirectURL)
            )
        )
    }

    func handle(url: URL) {
        client.auth.handle(url)
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
        guard account.status == .active else {
            try? await client.auth.signOut()
            throw BackendError.accountSuspended
        }
        return account
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = PostgresDate.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return decoder
    }

    // MARK: - Auth

    func restoreSession() async -> UserAccount? {
        guard let session = try? await client.auth.session else { return nil }
        return try? await ensureActive(account(id: session.user.id))
    }

    func signUp(email: String, password: String, role: UserRole) async throws -> UserAccount {
        let response = try await mapped {
            try await client.auth.signUp(email: email, password: password, data: ["role": .string(role.rawValue)], redirectTo: AppConfig.redirectURL)
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

    func deleteAccount() async throws {
        let _: [String: Bool] = try await invoke("delete-account", [:])
        try? await client.auth.signOut()
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

    func savePayoutAccount(_ account: PayoutAccount, iban: String?) async throws -> PayoutAccount {
        var body: [String: AnyJSON] = [
            "studio_id": .string(account.studioId.uuidString),
            "account_holder": .string(account.accountHolder),
        ]
        if let iban { body["iban"] = .string(iban) }
        return try await invoke("payout-account", body)
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

    func createBooking(_ request: BookingRequest) async throws -> Booking {
        try await invoke("create-booking", [
            "studio_id": .string(request.studio.id.uuidString),
            "session_type_id": .string(request.sessionType.id),
            "starts_at": .string(PostgresDate.format(request.startsAt)),
            "hours": .integer(request.hours),
            "add_ons": .array(request.addOns.filter { $0.value > 0 }.map { .object(["id": .string($0.key), "quantity": .integer($0.value)]) }),
            "notes": .string(request.notes),
        ])
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
        try await invoke("cancel-booking", ["booking_id": .string(id.uuidString), "reason": .string(reason)])
    }

    func rescheduleBooking(id: UUID, newStart: Date) async throws -> Booking {
        try await invoke("reschedule-booking", ["booking_id": .string(id.uuidString), "starts_at": .string(PostgresDate.format(newStart))])
    }

    func respondToBooking(id: UUID, accept: Bool, message: String?) async throws -> Booking {
        try await invoke("respond-booking", ["booking_id": .string(id.uuidString), "accept": .bool(accept), "message": message.map { .string($0) } ?? .null])
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
            "p_booking_id": bookingId.map { .string($0.uuidString) } ?? .null,
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

/// Postgres/PostgREST timestamp handling ("2026-09-24T10:00:00.123456+00:00" and variants).
enum PostgresDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var value = raw.replacingOccurrences(of: " ", with: "T")
        // Add a timezone when missing (realtime payloads for `timestamp` columns).
        if value.range(of: #"(Z|[+-]\d{2}(:?\d{2})?)$"#, options: .regularExpression) == nil { value += "Z" }
        // Normalise "+00" to "+00:00".
        if let range = value.range(of: #"[+-]\d{2}$"#, options: .regularExpression) { value.replaceSubrange(range, with: value[range] + ":00") }
        // ISO8601DateFormatter supports at most millisecond precision; trim microseconds.
        if let range = value.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = value[range].dropFirst()
            value.replaceSubrange(range, with: "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        return withFraction.date(from: value) ?? plain.date(from: value)
    }

    static func format(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}
