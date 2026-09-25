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
    /// Version of the terms & privacy policy the user accepted (GDPR consent record).
    var acceptedTermsVersion: String? = nil
    var acceptedTermsAt: Date? = nil
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

extension UserSettings {
    /// Tolerates missing keys so older/partial jsonb rows still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings()
        pushEnabled = try c.decodeIfPresent(Bool.self, forKey: .pushEnabled) ?? d.pushEnabled
        emailEnabled = try c.decodeIfPresent(Bool.self, forKey: .emailEnabled) ?? d.emailEnabled
        bookingUpdates = try c.decodeIfPresent(Bool.self, forKey: .bookingUpdates) ?? d.bookingUpdates
        messages = try c.decodeIfPresent(Bool.self, forKey: .messages) ?? d.messages
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? d.reminders
        reviewPrompts = try c.decodeIfPresent(Bool.self, forKey: .reviewPrompts) ?? d.reviewPrompts
        marketing = try c.decodeIfPresent(Bool.self, forKey: .marketing) ?? d.marketing
        searchRadiusKm = try c.decodeIfPresent(Double.self, forKey: .searchRadiusKm) ?? d.searchRadiusKm
        useMetricUnits = try c.decodeIfPresent(Bool.self, forKey: .useMetricUnits) ?? d.useMetricUnits
    }
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
    /// Cosmetic "EasySesh team" badge (set by admins).
    var hasAdminBadge: Bool? = nil
    /// Average of the ratings studios gave this artist (1–5), and how many.
    var ratingAverage: Double? = nil
    var reviewCount: Int? = nil

    static func empty(id: UUID) -> ArtistProfile {
        ArtistProfile(id: id, artistName: "", genres: [], city: "", bio: "", avatarUrl: nil, links: [], isVerified: false)
    }

    var isComplete: Bool { !artistName.trimmingCharacters(in: .whitespaces).isEmpty && !city.isEmpty }
}

struct SocialLink: Codable, Hashable, Identifiable {
    var platform: SocialPlatform
    var url: String
    var id: String { platform.rawValue + url }

    /// A tappable address, also when people typed just their username ("jugielewicz", "@name")
    /// or a site without "https://".
    var resolvedURL: URL? { SocialLink.resolve(url, platform: platform) }

    static func resolve(_ raw: String, platform: SocialPlatform) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: text) }
        // Looks like a domain or path ("open.spotify.com/…", "mysite.dk")
        if text.contains(".") && !text.hasPrefix("@") && !text.contains(" ") {
            return URL(string: "https://" + text)
        }
        let handle = text.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
        switch platform {
        case .instagram: return URL(string: "https://www.instagram.com/\(handle)")
        case .tiktok: return URL(string: "https://www.tiktok.com/@\(handle)")
        case .youtube: return URL(string: "https://www.youtube.com/@\(handle)")
        case .soundcloud: return URL(string: "https://soundcloud.com/\(handle)")
        case .spotify: return URL(string: "https://open.spotify.com/search/\(handle)")
        case .appleMusic: return URL(string: "https://music.apple.com/search?term=\(handle)")
        case .website: return URL(string: "https://\(handle)")
        }
    }
}
