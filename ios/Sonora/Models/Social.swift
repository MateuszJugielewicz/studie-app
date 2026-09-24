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
}

struct SupportMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var ticketId: UUID
    var senderId: UUID?
    var fromAdmin: Bool
    var body: String
    var createdAt: Date
}
