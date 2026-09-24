import Foundation

enum BackendError: LocalizedError, Equatable {
    case notAuthenticated
    case notFound
    case forbidden
    case accountSuspended
    case invalidCredentials
    case emailInUse
    case slotUnavailable
    case validation(String)
    case paymentFailed(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Please sign in to continue."
        case .notFound: "We couldn't find that."
        case .forbidden: "You don't have access to this."
        case .accountSuspended: "This account is suspended. Contact support."
        case .invalidCredentials: "Wrong email or password."
        case .emailInUse: "An account with this email already exists."
        case .slotUnavailable: "That time is no longer available. Please pick another slot."
        case .validation(let message): message
        case .paymentFailed(let message): "Payment failed: \(message)"
        case .server(let message): message
        }
    }
}

/// Details the payment sheet needs to charge a booking.
struct PaymentIntentInfo: Hashable {
    var bookingId: UUID
    var clientSecret: String
    var customerId: String?
    var ephemeralKey: String?
    var amount: Int
    var currency: String
    /// Studios on request-to-book authorise now and capture on acceptance.
    var captureLater: Bool
}

/// Everything the iOS app needs from the server. Implemented by `SupabaseBackend`;
/// the unit tests use an in-memory `MockBackend`.
@MainActor
protocol Backend: AnyObject {
    // MARK: Auth
    func restoreSession() async -> UserAccount?
    func signUp(email: String, password: String, role: UserRole) async throws -> UserAccount
    func signIn(email: String, password: String) async throws -> UserAccount
    func signInWithApple(idToken: String, nonce: String, role: UserRole) async throws -> UserAccount
    func signInWithGoogle(role: UserRole) async throws -> UserAccount
    func sendPasswordReset(email: String) async throws
    func signOut() async
    func deleteAccount() async throws
    func updateSettings(_ settings: UserSettings) async throws -> UserAccount
    /// Records acceptance of the current terms & privacy policy (GDPR consent record).
    func acceptTerms(version: String) async throws -> UserAccount
    /// GDPR data export: everything stored about the signed-in user, as JSON.
    func exportPersonalData() async throws -> Data

    // MARK: Profiles
    func artistProfile(id: UUID) async throws -> ArtistProfile?
    func saveArtistProfile(_ profile: ArtistProfile) async throws -> ArtistProfile
    func uploadImage(_ data: Data, folder: String) async throws -> String

    // MARK: Studios
    func publishedStudios() async throws -> [Studio]
    func studio(id: UUID) async throws -> Studio
    func ownedStudio() async throws -> Studio?
    func saveStudio(_ studio: Studio) async throws -> Studio
    func submitStudioForReview(id: UUID) async throws -> Studio
    func setStudioActive(id: UUID, isActive: Bool) async throws -> Studio
    func payoutAccount(studioId: UUID) async throws -> PayoutAccount?
    func savePayoutAccount(_ account: PayoutAccount, iban: String?) async throws -> PayoutAccount
    /// Hosted onboarding link where the studio adds bank details (Stripe Connect).
    func payoutOnboardingURL(studioId: UUID) async throws -> URL?
    /// Occupied periods (bookings + blocks) used to compute availability.
    func busyIntervals(studioIds: [UUID], from: Date, to: Date) async throws -> [UUID: [DateInterval]]
    func blockedSlots(studioId: UUID) async throws -> [BlockedSlot]
    func addBlockedSlot(_ slot: BlockedSlot) async throws -> BlockedSlot
    func removeBlockedSlot(id: UUID) async throws

    // MARK: Bookings
    func createBooking(_ request: BookingRequest) async throws -> Booking
    func preparePayment(bookingId: UUID, method: PaymentMethod) async throws -> PaymentIntentInfo
    /// Called after the payment sheet reports success. Returns the updated booking.
    func confirmPayment(bookingId: UUID, method: PaymentMethod) async throws -> Booking
    /// Artist pays cash at the studio instead of in the app.
    func confirmCashBooking(bookingId: UUID) async throws -> Booking
    /// Studio confirms it received the cash for a session.
    func markCashReceived(bookingId: UUID) async throws -> Booking
    func booking(id: UUID) async throws -> Booking
    func artistBookings() async throws -> [Booking]
    func studioBookings(studioId: UUID) async throws -> [Booking]
    func cancelBooking(id: UUID, reason: String) async throws -> Booking
    func rescheduleBooking(id: UUID, newStart: Date) async throws -> Booking
    func respondToBooking(id: UUID, accept: Bool, message: String?) async throws -> Booking
    func openDispute(bookingId: UUID, reason: String) async throws

    // MARK: Payments
    func transactions(bookingId: UUID) async throws -> [PaymentTransaction]
    func payouts(studioId: UUID) async throws -> [Payout]
    /// Platform fees owed for cash bookings and their settlements.
    func feeLedger(studioId: UUID) async throws -> [FeeLedgerEntry]

    // MARK: Chat
    func conversations() async throws -> [Conversation]
    func conversation(studioId: UUID, bookingId: UUID?) async throws -> Conversation
    func messages(conversationId: UUID) async throws -> [ChatMessage]
    func sendMessage(conversationId: UUID, body: String) async throws -> ChatMessage
    func markConversationRead(id: UUID) async throws
    /// Live stream of new messages in a conversation.
    func messageStream(conversationId: UUID) -> AsyncStream<ChatMessage>

    // MARK: Reviews & moderation
    func reviews(studioId: UUID) async throws -> [Review]
    func submitReview(_ review: Review) async throws -> Review
    func replyToReview(id: UUID, reply: String) async throws -> Review
    func report(target: ReportTarget, targetId: UUID, reason: ReportReason, details: String) async throws

    // MARK: Notifications
    func notifications() async throws -> [AppNotification]
    func markNotificationRead(id: UUID) async throws
    func markAllNotificationsRead() async throws
    func registerPushToken(_ token: String) async throws
}
