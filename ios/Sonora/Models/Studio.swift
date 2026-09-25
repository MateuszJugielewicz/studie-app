import Foundation
import CoreLocation

/// A studio listing (`studios` table). Nested value types are stored as jsonb.
struct Studio: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerId: UUID
    var name: String
    var tagline: String
    var description: String
    var photoUrls: [String]
    var videoUrl: String?
    var address: StudioAddress
    var latitude: Double
    var longitude: Double
    var contact: StudioContact
    var currency: String
    /// Lowest hourly rate across session types, in minor units. Kept in sync by `normalized()`.
    var priceFrom: Int
    var sessionTypes: [SessionType]
    var addOns: [ServiceAddOn]
    var facilities: [Facility]
    var equipment: [EquipmentItem]
    var engineers: [StudioPerson]
    var capacity: Int
    var genres: [Genre]
    var openingHours: [OpeningHours]
    var rules: [String]
    var bookingPolicy: BookingPolicy
    var status: StudioStatus
    var isActive: Bool
    var isVerified: Bool
    var adminNote: String?
    var ratingAverage: Double
    var reviewCount: Int
    var bookingCount: Int
    var createdAt: Date
    var submittedAt: Date?
    /// IANA time zone of the studio. Opening hours are interpreted in this zone.
    var timezone: String? = nil
    /// Cosmetic "EasySesh team" badge (set by admins).
    var hasAdminBadge: Bool? = nil
    /// Special tags only admins can add, e.g. "Staff pick".
    var adminTags: [String]? = nil
    /// Paid or granted promotion: shown first in search with a "Promoted" tag until this date.
    var promotedUntil: Date? = nil
    /// Special deal: this studio's platform fee in percent (default 10).
    var platformFeePercent: Int? = nil

    var feePercent: Int { platformFeePercent ?? PlatformConfig.platformFeePercent }

    var isPromoted: Bool { (promotedUntil ?? .distantPast) > .now }
    var showsAdminBadge: Bool { hasAdminBadge == true }
    var specialTags: [String] { adminTags ?? [] }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    var timeZone: TimeZone { timezone.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// Visible to artists only when approved by an admin and switched on.
    var isBookable: Bool { status == .approved && isActive }

    var microphones: [EquipmentItem] { equipment.filter { $0.category == .microphone } }

    var offersMixing: Bool { addOns.contains { $0.kind == .mixing } }
    var offersMastering: Bool { addOns.contains { $0.kind == .mastering } }

    func sessionType(id: String) -> SessionType? { sessionTypes.first { $0.id == id } }

    func hours(for weekday: Int) -> OpeningHours? { openingHours.first { $0.weekday == weekday } }

    /// Recomputes derived fields before saving.
    func normalized() -> Studio {
        var copy = self
        copy.priceFrom = sessionTypes.map(\.hourlyRate).min() ?? 0
        return copy
    }

    static func newDraft(ownerId: UUID) -> Studio {
        Studio(
            id: UUID(),
            ownerId: ownerId,
            name: "",
            tagline: "",
            description: "",
            photoUrls: [],
            videoUrl: nil,
            address: StudioAddress(street: "", postalCode: "", city: "", area: "", country: ""),
            latitude: 0,
            longitude: 0,
            contact: StudioContact(phone: "", email: "", website: ""),
            currency: "EUR",
            priceFrom: 0,
            sessionTypes: [SessionType(id: "recording", name: "Recording", details: "", hourlyRate: 3000, minimumHours: 2, includesEngineer: false)],
            addOns: [],
            facilities: [],
            equipment: [],
            engineers: [],
            capacity: 4,
            genres: [],
            openingHours: OpeningHours.standardWeek,
            rules: [],
            bookingPolicy: BookingPolicy(),
            status: .draft,
            isActive: false,
            isVerified: false,
            adminNote: nil,
            ratingAverage: 0,
            reviewCount: 0,
            bookingCount: 0,
            createdAt: .now,
            submittedAt: nil
        )
    }
}

struct StudioAddress: Codable, Hashable {
    var street: String
    var postalCode: String
    var city: String
    /// Neighbourhood / area shown publicly, e.g. "Exarchia".
    var area: String
    var country: String

    var singleLine: String {
        [street, [postalCode, city].filter { !$0.isEmpty }.joined(separator: " "), country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var publicArea: String { [area, city].filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct StudioContact: Codable, Hashable {
    var phone: String
    var email: String
    var website: String
}

struct SessionType: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var details: String
    /// Price per hour in minor units (cents).
    var hourlyRate: Int
    var minimumHours: Int
    var includesEngineer: Bool
}

enum AddOnKind: String, Codable, CaseIterable, Hashable {
    case engineer, producer, mixing, mastering, other

    var title: String {
        switch self {
        case .engineer: "Engineer"
        case .producer: "Producer"
        case .mixing: "Mixing"
        case .mastering: "Mastering"
        case .other: "Extra"
        }
    }
}

enum PriceUnit: String, Codable, CaseIterable, Hashable {
    case perHour = "per_hour"
    case perSession = "per_session"
    case perTrack = "per_track"

    var suffix: String {
        switch self {
        case .perHour: "/ hour"
        case .perSession: "/ session"
        case .perTrack: "/ track"
        }
    }
}

struct ServiceAddOn: Codable, Hashable, Identifiable {
    var id: String
    var kind: AddOnKind
    var name: String
    var price: Int
    var unit: PriceUnit
}

struct EquipmentItem: Codable, Hashable, Identifiable {
    var id: String
    var category: EquipmentCategory
    var name: String
}

struct StudioPerson: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var role: String
    var bio: String
}

/// `weekday` follows `Calendar.component(.weekday)`: 1 = Sunday … 7 = Saturday.
/// Times are minutes after midnight. `closesAt` may exceed 1440 for studios open past midnight.
struct OpeningHours: Codable, Hashable, Identifiable {
    var weekday: Int
    var isClosed: Bool
    var opensAt: Int
    var closesAt: Int

    var id: Int { weekday }

    var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }

    var label: String {
        isClosed ? "Closed" : "\(Self.format(opensAt)) – \(Self.format(closesAt))"
    }

    static func format(_ minutes: Int) -> String {
        let m = minutes % (24 * 60)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Monday-first ordering for display.
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    static var standardWeek: [OpeningHours] {
        (1...7).map { OpeningHours(weekday: $0, isClosed: false, opensAt: 10 * 60, closesAt: 22 * 60) }
    }
}

struct BookingPolicy: Codable, Hashable {
    /// When false the studio must accept each request (card is authorised, charged on acceptance).
    var instantBook: Bool = true
    var cancellationPolicy: CancellationPolicy = .moderate
    /// 0 = full payment up front. Otherwise the percentage of the subtotal charged at booking.
    var depositPercent: Int = 0
    var minimumNoticeHours: Int = 12
    var maxAdvanceDays: Int = 90
    var bufferMinutes: Int = 0
    var terms: String = ""
    /// Artists may choose to pay cash at the session (only without a card deposit).
    var acceptsCash: Bool = true
    /// Artists can check in when they arrive (recommended against fraud). When off, EasySesh
    /// can't promise a refund if something goes wrong.
    var checkInEnabled: Bool = true
}

extension BookingPolicy {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BookingPolicy()
        instantBook = try c.decodeIfPresent(Bool.self, forKey: .instantBook) ?? d.instantBook
        cancellationPolicy = try c.decodeIfPresent(CancellationPolicy.self, forKey: .cancellationPolicy) ?? d.cancellationPolicy
        depositPercent = try c.decodeIfPresent(Int.self, forKey: .depositPercent) ?? d.depositPercent
        minimumNoticeHours = try c.decodeIfPresent(Int.self, forKey: .minimumNoticeHours) ?? d.minimumNoticeHours
        maxAdvanceDays = try c.decodeIfPresent(Int.self, forKey: .maxAdvanceDays) ?? d.maxAdvanceDays
        bufferMinutes = try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? d.bufferMinutes
        terms = try c.decodeIfPresent(String.self, forKey: .terms) ?? d.terms
        acceptsCash = try c.decodeIfPresent(Bool.self, forKey: .acceptsCash) ?? d.acceptsCash
        checkInEnabled = try c.decodeIfPresent(Bool.self, forKey: .checkInEnabled) ?? d.checkInEnabled
    }
}

/// Private payout details (`studio_payout_accounts` table, owner + admin only).
struct PayoutAccount: Codable, Hashable {
    var studioId: UUID
    var accountHolder: String
    var ibanLast4: String
    var stripeAccountId: String?
    var payoutsEnabled: Bool
}

/// A studio-blocked period (maintenance, private use, etc.).
struct BlockedSlot: Codable, Hashable, Identifiable {
    let id: UUID
    var studioId: UUID
    var startsAt: Date
    var endsAt: Date
    var reason: String

    var interval: DateInterval { DateInterval(start: startsAt, end: max(startsAt, endsAt)) }
}
