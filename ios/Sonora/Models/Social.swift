import Foundation

/// Chat is always scoped to one artist + one studio, optionally tied to a booking.
/// There are no artist-to-artist or group conversations by design.
struct Conversation: Codable, Identifiable, Hashable {
    let id: UUID
    var artistId: UUID
    var studioId: UUID
    var bookingId: UUID?
    var artistName: String
    var studioName: String
    var studioPhotoUrl: String?
    var lastMessagePreview: String
    var lastMessageAt: Date
    var artistUnread: Int
    var studioUnread: Int
    /// nil on databases that predate message requests (treated as accepted).
    var requestStatus: ConversationRequestStatus?
    var startedByStudio: Bool?
    var artistAvatarUrl: String?

    func unread(for role: UserRole) -> Int { role == .artist ? artistUnread : studioUnread }

    var status: ConversationRequestStatus { requestStatus ?? .accepted }
    /// A studio wrote first and the artist hasn't accepted yet.
    var isPendingRequest: Bool { status == .pending }
    var isDeclined: Bool { status == .declined }

    /// Unread messages that count towards the tab badge. Requests and declined threads don't.
    func badgeCount(for role: UserRole) -> Int {
        if role == .artist && status != .accepted { return 0 }
        return unread(for: role)
    }

    func title(for role: UserRole) -> String { role == .artist ? studioName : artistName }
}

enum ConversationRequestStatus: String, Codable, Hashable {
    case accepted, pending, declined
}

/// Artist found by a studio when starting a new conversation.
struct ArtistSearchResult: Codable, Identifiable, Hashable {
    let id: UUID
    var artistName: String
    var city: String
    var genres: [String]
    var avatarUrl: String?
    var isVerified: Bool
    /// Has booked this studio before (skips the message request).
    var hasBooked: Bool
    var hasAdminBadge: Bool? = nil
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var conversationId: UUID
    /// nil for system messages.
    var senderId: UUID?
    var kind: MessageKind
    var body: String
    var createdAt: Date
}

struct Review: Codable, Identifiable, Hashable {
    let id: UUID
    var bookingId: UUID
    var studioId: UUID
    var artistId: UUID
    var artistName: String
    var rating: Int
    var facilitiesRating: Int
    var experienceRating: Int
    /// nil when the session had no engineer/producer.
    var engineerRating: Int?
    var text: String
    var studioReply: String?
    var studioRepliedAt: Date?
    var isHidden: Bool
    var createdAt: Date
}

struct AppNotification: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var kind: NotificationKind
    var title: String
    var body: String
    var isRead: Bool
    var bookingId: UUID?
    var conversationId: UUID?
    var studioId: UUID?
    var createdAt: Date
}

struct Report: Codable, Identifiable, Hashable {
    let id: UUID
    var reporterId: UUID
    var targetType: ReportTarget
    var targetId: UUID
    var reason: ReportReason
    var details: String
    var status: ReportStatus
    var createdAt: Date
}

// MARK: - Support

enum SupportCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case account, booking, payment, studio, bug, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account & login"
        case .booking: "A booking"
        case .payment: "Payments & refunds"
        case .studio: "My studio listing"
        case .bug: "Something isn't working"
        case .other: "Something else"
        }
    }

    var symbol: String {
        switch self {
        case .account: "person.crop.circle"
        case .booking: "calendar"
        case .payment: "creditcard"
        case .studio: "music.mic"
        case .bug: "ladybug"
        case .other: "questionmark.bubble"
        }
    }
}

enum SupportTicketStatus: String, Codable, Hashable {
    /// Waiting for Sonora.
    case open
    /// Sonora replied; waiting for the user.
    case answered
    case closed

    var title: String {
        switch self {
        case .open: "Waiting for EasySesh"
        case .answered: "EasySesh replied"
        case .closed: "Closed"
        }
    }
}

struct SupportTicket: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var subject: String
    var category: SupportCategory
    var bookingId: UUID?
    var status: SupportTicketStatus
    var userUnread: Int
    var lastMessagePreview: String
    var lastMessageAt: Date
    var createdAt: Date
    /// 1–5 stars the user gave after the request was closed.
    var rating: Int?
    var ratingComment: String?
}

struct SupportMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var ticketId: UUID
    var senderId: UUID?
    var fromAdmin: Bool
    var body: String
    var createdAt: Date
}

// MARK: - Artist ratings (given by studios)

struct ArtistReview: Codable, Identifiable, Hashable {
    let id: UUID
    var bookingId: UUID
    var studioId: UUID
    var artistId: UUID
    var studioName: String
    var rating: Int
    var text: String
    var createdAt: Date
}

// MARK: - Promotions

enum PromotionPackage: String, Codable, CaseIterable, Identifiable, Hashable {
    case week
    case twoWeeks = "two_weeks"
    case month
    case custom

    var id: String { rawValue }
    static var purchasable: [PromotionPackage] { [.week, .twoWeeks, .month] }

    var days: Int {
        switch self {
        case .week: 7
        case .twoWeeks: 14
        case .month: 30
        case .custom: 0
        }
    }

    var title: String {
        switch self {
        case .week: "1 week"
        case .twoWeeks: "2 weeks"
        case .month: "1 month"
        case .custom: "Promotion"
        }
    }

    /// Same table as `promotion_price` in the database (which decides what is charged).
    func price(currency: String) -> Int {
        let table: [String: [Int]] = [
            "DKK": [14900, 26900, 44900], "SEK": [21900, 39900, 65900], "NOK": [21900, 39900, 65900],
            "GBP": [1600, 2900, 4900], "USD": [2100, 3900, 6500], "PLN": [8900, 15900, 25900],
        ]
        let prices = table[currency.uppercased()] ?? [1900, 3500, 5900]
        switch self {
        case .week: return prices[0]
        case .twoWeeks: return prices[1]
        case .month: return prices[2]
        case .custom: return 0
        }
    }
}

enum PromotionStatus: String, Codable, Hashable {
    case pending, active, expired, cancelled
}

struct StudioPromotion: Codable, Identifiable, Hashable {
    let id: UUID
    var studioId: UUID
    var package: PromotionPackage
    var days: Int
    var amount: Int
    var currency: String
    var status: PromotionStatus
    var source: String
    var startsAt: Date?
    var endsAt: Date?
    var createdAt: Date
}

// MARK: - Studio ↔ artist profile connection

struct StudioArtistLink: Codable, Hashable {
    var studioId: UUID
    var artistId: UUID
    var status: String
    var createdAt: Date

    var isAccepted: Bool { status == "accepted" }
}

// MARK: - Rating disputes

enum RatingKind: String, Codable, Hashable {
    /// An artist's review of a studio (disputed by the studio).
    case studioReview = "studio_review"
    /// A studio's rating of an artist (disputed by the artist).
    case artistReview = "artist_review"
}

// MARK: - Platform fee invoices

/// A warning from the EasySesh team, shown until the user acknowledges it.
struct ModerationWarning: Codable, Identifiable, Hashable {
    let id: UUID
    var reason: String
    var createdAt: Date
    var acknowledgedAt: Date?
}

/// An update note written by the EasySesh team ("What's new"). A legal update means everyone
/// has to read and accept the documents again.
struct ChangelogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var version: String
    var title: String
    var body: String
    var audience: String
    var isLegalUpdate: Bool
    var publishedAt: Date

    func isFor(_ role: UserRole) -> Bool { audience == "all" || audience == role.rawValue }
}

extension LegalDocument {
    /// Terms versions are dates ("2026-09-25", optionally with a suffix), so they compare as text.
    static func newest(_ a: String, _ b: String?) -> String {
        guard let b, b > a else { return a }
        return b
    }
}

struct FeeInvoice: Codable, Identifiable, Hashable {
    let id: UUID
    var studioId: UUID
    var amount: Int
    var currency: String
    var status: String
    var hostedInvoiceUrl: String?
    var dueAt: Date?
    var createdAt: Date

    var isOverdue: Bool { status == "open" && (dueAt ?? .distantFuture) < .now }
    var isInCollections: Bool { status == "collections" }
}
