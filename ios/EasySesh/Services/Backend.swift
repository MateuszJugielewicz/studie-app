import Foundation

enum BackendError: LocalizedError, Equatable {
    case notAuthenticated
    case notFound
    case forbidden
    case accountSuspended
    /// Suspended or banned by the EasySesh team, possibly for a limited period.
    case accountRestricted(banned: Bool, until: Date?, reason: String?)
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
        case .accountRestricted(let banned, let until, let reason): Self.restrictionMessage(banned: banned, until: until, reason: reason)
        case .invalidCredentials: "Wrong email or password."
        case .emailInUse: "An account with this email already exists."
        case .slotUnavailable: "That time is no longer available. Please pick another slot."
        case .validation(let message): message
        case .paymentFailed(let message): "Payment failed: \(message)"
        case .server(let message): message
        }
    }
}

extension BackendError {
    static func restrictionMessage(banned: Bool, until: Date?, reason: String?) -> String {
        var parts: [String] = [banned ? L10n.tr("This account is banned.") : L10n.tr("This account is suspended.")]
        if let until {
            let date = until.formatted(date: .abbreviated, time: .shortened)
            parts.append(L10n.format("Until %@.", date))
        } else {
            parts.append(L10n.tr("Contact support if you think this is a mistake."))
        }
        if let reason, !reason.isEmpty { parts.append(L10n.format("Reason: %@", reason)) }
        return parts.joined(separator: " ")
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
    func changePassword(to newPassword: String) async throws
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
    /// Re-reads the payout status from Stripe (after the studio returns from Stripe's pages).
    func syncPayoutAccount(studioId: UUID) async throws -> PayoutAccount
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
    /// Artist checks in on arrival (location optional).
    func checkIn(bookingId: UUID, latitude: Double?, longitude: Double?) async throws -> Booking
    /// Studio confirms the artist arrived.
    func confirmArrival(bookingId: UUID) async throws -> Booking

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
    /// Studio → artist: starts (or continues) a conversation. New artists get it as a message request.
    func startConversation(artistId: UUID, body: String) async throws -> Conversation
    func respondToMessageRequest(conversationId: UUID, accept: Bool) async throws -> Conversation
    /// Artists a studio can message. An empty query returns artists who booked the studio.
    func searchArtists(query: String) async throws -> [ArtistSearchResult]
    /// Live stream of new messages in a conversation.
    func messageStream(conversationId: UUID) -> AsyncStream<ChatMessage>

    // MARK: Reviews & moderation
    func reviews(studioId: UUID) async throws -> [Review]
    func submitReview(_ review: Review) async throws -> Review
    func replyToReview(id: UUID, reply: String) async throws -> Review
    func report(target: ReportTarget, targetId: UUID, reason: ReportReason, details: String) async throws

    // MARK: Support
    func supportTickets() async throws -> [SupportTicket]
    func createSupportTicket(subject: String, category: SupportCategory, body: String, bookingId: UUID?) async throws -> SupportTicket
    func supportMessages(ticketId: UUID) async throws -> [SupportMessage]
    func sendSupportMessage(ticketId: UUID, body: String) async throws -> SupportMessage
    func markSupportTicketRead(id: UUID) async throws
    func closeSupportTicket(id: UUID) async throws -> SupportTicket
    /// Rate a closed request (1–5 stars, optional comment).
    func rateSupportTicket(id: UUID, rating: Int, comment: String) async throws -> SupportTicket

    // MARK: Promotions
    func promotions(studioId: UUID) async throws -> [StudioPromotion]
    /// Orders a promotion (pending until paid in the app or activated by EasySesh).
    func requestPromotion(_ package: PromotionPackage) async throws -> StudioPromotion
    func cancelPromotionRequest(id: UUID) async throws
    /// Card payment for a pending promotion (needs Stripe).
    func preparePromotionPayment(promotionId: UUID) async throws -> PaymentIntentInfo
    func confirmPromotionPayment(promotionId: UUID) async throws

    // MARK: Artist ratings
    func reviewArtist(bookingId: UUID, rating: Int, text: String) async throws -> ArtistReview
    func artistReviews(artistId: UUID) async throws -> [ArtistReview]
    func artistReview(bookingId: UUID) async throws -> ArtistReview?

    // MARK: Studio ↔ artist profile
    /// Accepted connection for a studio (or pending, for its owner).
    func studioArtistLink(studioId: UUID) async throws -> StudioArtistLink?
    /// Connections that involve this artist (accepted, and pending ones for the artist).
    func artistStudioLinks(artistId: UUID) async throws -> [StudioArtistLink]
    func requestStudioArtistLink(artistId: UUID) async throws -> StudioArtistLink
    func respondStudioArtistLink(studioId: UUID, accept: Bool) async throws
    func removeStudioArtistLink(studioId: UUID) async throws

    // MARK: Rating disputes & fee invoices
    func disputeRating(kind: RatingKind, reviewId: UUID, reason: String) async throws

    // Moderation
    func unacknowledgedWarnings() async throws -> [ModerationWarning]
    func acknowledgeWarning(id: UUID) async throws

    // Changelog & terms updates
    func changelog() async throws -> [ChangelogEntry]
    /// The terms version everyone must have accepted (the admin bumps it with a legal update).
    func currentTermsVersion() async throws -> String
    func feeInvoices(studioId: UUID) async throws -> [FeeInvoice]

    // MARK: Notifications
    func deleteNotification(id: UUID) async throws
    func deleteAllNotifications() async throws
    func notifications() async throws -> [AppNotification]
    func markNotificationRead(id: UUID) async throws
    func markAllNotificationsRead() async throws
    func registerPushToken(_ token: String) async throws
}
