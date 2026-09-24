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

    func unread(for role: UserRole) -> Int { role == .artist ? artistUnread : studioUnread }

    func title(for role: UserRole) -> String { role == .artist ? studioName : artistName }
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
