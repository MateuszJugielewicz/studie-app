import Foundation

/// The account row (`profiles` table). One per auth user.
struct UserAccount: Codable, Identifiable, Hashable {
    let id: UUID
    var email: String
    var role: UserRole
    var status: AccountStatus
    var isVerified: Bool
    var settings: UserSettings
    var createdAt: Date
}

struct UserSettings: Codable, Hashable {
    var pushEnabled: Bool = true
    var emailEnabled: Bool = true
    var bookingUpdates: Bool = true
    var messages: Bool = true
    var reminders: Bool = true
    var reviewPrompts: Bool = true
    var marketing: Bool = false
    var searchRadiusKm: Double = 10
    var useMetricUnits: Bool = true
}

/// Public artist profile (`artist_profiles` table). `id` equals the account id.
struct ArtistProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var artistName: String
    var genres: [Genre]
    var city: String
    var bio: String
    var avatarUrl: String?
    var links: [SocialLink]
    var isVerified: Bool

    static func empty(id: UUID) -> ArtistProfile {
        ArtistProfile(id: id, artistName: "", genres: [], city: "", bio: "", avatarUrl: nil, links: [], isVerified: false)
    }

    var isComplete: Bool { !artistName.trimmingCharacters(in: .whitespaces).isEmpty && !city.isEmpty }
}

struct SocialLink: Codable, Hashable, Identifiable {
    var platform: SocialPlatform
    var url: String
    var id: String { platform.rawValue + url }
}
