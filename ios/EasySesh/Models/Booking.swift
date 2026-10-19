import Foundation

struct Booking: Codable, Identifiable, Hashable {
    let id: UUID
    var reference: String
    var artistId: UUID
    var studioId: UUID
    var artistName: String
    var studioName: String
    var sessionTypeId: String
    var sessionTypeName: String
    var startsAt: Date
    var endsAt: Date
    var hours: Int
    var addOns: [BookedAddOn]
    var status: BookingStatus
    var paymentStatus: PaymentStatus
    var price: PriceBreakdown
    var notes: String
    var cancellationReason: String?
    var cancelledBy: UserRole?
    var refundAmount: Int
    var hasReview: Bool
    var createdAt: Date
    var updatedAt: Date
    var paymentMethod: PaymentMethod? = nil
    var cashReceivedAt: Date? = nil
    /// Check-in on arrival (optional, recommended): when the artist checked in and how far away.
    var artistCheckedInAt: Date? = nil
    var artistCheckInDistanceM: Int? = nil
    var studioConfirmedArrivalAt: Date? = nil

    /// Check-in opens 1 hour before the session and closes when it ends.
    func canCheckIn(now: Date = .now) -> Bool {
        status == .confirmed && artistCheckedInAt == nil && now >= startsAt.addingTimeInterval(-3600) && now <= endsAt
    }

    var isCash: Bool { paymentMethod == .cash }

    var interval: DateInterval { DateInterval(start: startsAt, end: endsAt) }

    var isUpcoming: Bool { endsAt > .now && status.isActive }

    var canCancel: Bool { status.isActive && startsAt > .now }
    var canReschedule: Bool { status == .confirmed && startsAt > .now }
    var canReview: Bool { status == .completed && !hasReview }
}

struct BookedAddOn: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var quantity: Int
    var amount: Int
}

/// Every amount is in minor units of `currency`.
struct PriceBreakdown: Codable, Hashable {
    var currency: String
    var hourlyRate: Int
    var hours: Int
    var sessionAmount: Int
    var addOnsAmount: Int
    /// session + add-ons: what the studio charges.
    var subtotal: Int
    /// Platform fee paid by the artist on top of the subtotal.
    var serviceFee: Int
    var total: Int
    /// Share of the subtotal charged at booking when the studio requires a deposit (0 when paying in full).
    var depositAmount: Int
    var dueNow: Int
    var dueLater: Int
    /// Commission the platform keeps from the studio.
    var studioCommission: Int
    var studioPayout: Int
    /// Discounts, computed by the server (studio offers and promo codes). An EasySesh promo code is
    /// paid by EasySesh and stored as a negative `serviceFee`.
    var originalSubtotal: Int? = nil
    var offerDiscount: Int? = nil
    var promoDiscount: Int? = nil
    var promoCode: String? = nil
    var discounts: [PriceDiscount]? = nil

    var platformRevenue: Int { serviceFee + studioCommission }
}

struct PriceDiscount: Codable, Hashable {
    var label: String
    var percent: Int
    var amount: Int
    /// "offer", "studio_code" or "easysesh_code".
    var kind: String
}

/// A studio's automatic deal, e.g. "Mixing 50% off".
struct StudioOffer: Codable, Identifiable, Hashable {
    let id: UUID
    var studioId: UUID
    var title: String
    var percentOff: Int
    /// everything | sessions | add_ons | session_type | add_on
    var appliesTo: String
    var targetId: String?
    var endsAt: Date?
    var isActive: Bool

    var isLive: Bool { isActive && (endsAt.map { $0 > .now } ?? true) }

    private enum CodingKeys: String, CodingKey { case id, studioId, title, percentOff, appliesTo, targetId, endsAt, isActive }

    /// Saved with upsert, so empty values are sent as null (otherwise clearing them wouldn't save).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(studioId, forKey: .studioId)
        try c.encode(title, forKey: .title)
        try c.encode(percentOff, forKey: .percentOff)
        try c.encode(appliesTo, forKey: .appliesTo)
        try c.encode(targetId, forKey: .targetId)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(isActive, forKey: .isActive)
    }

    func targetName(in studio: Studio) -> String {
        switch appliesTo {
        case "sessions": return L10n.tr("All sessions")
        case "add_ons": return L10n.tr("All extras")
        case "session_type": return studio.sessionTypes.first { $0.id == targetId }?.name ?? L10n.tr("Session")
        case "add_on": return studio.addOns.first { $0.id == targetId }?.name ?? L10n.tr("Extra")
        default: return L10n.tr("Everything")
        }
    }
}

/// A code artists type in at checkout. `studioId` nil = an EasySesh code (made by an admin).
struct PromoCode: Codable, Identifiable, Hashable {
    let id: UUID
    var studioId: UUID?
    var code: String
    var percentOff: Int
    var description: String = ""
    var endsAt: Date?
    var maxUses: Int?
    var maxUsesPerUser: Int = 1
    var isActive: Bool = true
    /// Bookings that used it (from `promo_code_usage`; not stored).
    var uses: Int?

    private enum CodingKeys: String, CodingKey { case id, studioId, code, percentOff, description, endsAt, maxUses, maxUsesPerUser, isActive, uses }

    /// Saved with upsert, so empty values are sent as null; `uses` isn't a column.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(studioId, forKey: .studioId)
        try c.encode(code, forKey: .code)
        try c.encode(percentOff, forKey: .percentOff)
        try c.encode(description, forKey: .description)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(maxUses, forKey: .maxUses)
        try c.encode(maxUsesPerUser, forKey: .maxUsesPerUser)
        try c.encode(isActive, forKey: .isActive)
    }
}

/// Result of checking a promo code at checkout.
struct PromoCheck: Codable, Hashable {
    var code: String
    var percentOff: Int
    var description: String
    var byEasysesh: Bool
}

/// Input for creating a booking.
struct BookingRequest: Hashable {
    var studio: Studio
    var sessionType: SessionType
    var startsAt: Date
    var hours: Int
    var addOns: [String: Int]
    var notes: String
    var promoCode: String? = nil
}

/// A payment-side movement of money (`transactions` table).
struct PaymentTransaction: Codable, Identifiable, Hashable {
    let id: UUID
    var bookingId: UUID
    var studioId: UUID
    var artistId: UUID
    var kind: TransactionKind
    var method: PaymentMethod
    var status: TransactionStatus
    var amount: Int
    var platformFee: Int
    var currency: String
    var receiptNumber: String
    var cardBrand: String?
    var cardLast4: String?
    var failureReason: String?
    var providerReference: String?
    var createdAt: Date
}

struct Payout: Codable, Identifiable, Hashable {
    let id: UUID
    var studioId: UUID
    var amount: Int
    var currency: String
    var status: PayoutStatus
    var scheduledFor: Date
    var paidAt: Date?
    var bookingIds: [UUID]
}

struct EarningsSummary: Hashable {
    var currency: String
    var grossThisMonth: Int
    var netThisMonth: Int
    var netAllTime: Int
    var pendingPayout: Int
    var completedSessions: Int
    var upcomingSessions: Int
    var hoursBooked: Int
    /// Net per calendar month, oldest first (last 6 months).
    var monthly: [MonthlyAmount]
}

struct MonthlyAmount: Hashable, Identifiable {
    var month: Date
    var amount: Int
    var id: Date { month }
}

/// Platform fees a studio owes EasySesh for cash bookings, and how they were settled.
/// Positive amounts are owed, negative amounts are settlements.
struct FeeLedgerEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case cashCommission = "cash_commission"
        case payoutOffset = "payout_offset"
        case invoicePayment = "invoice_payment"
        case manualPayment = "manual_payment"
        case waiver

        var title: String {
            switch self {
            case .cashCommission: "Platform fee (cash booking)"
            case .payoutOffset: "Deducted from payout"
            case .invoicePayment: "Invoice paid"
            case .manualPayment: "Payment received"
            case .waiver: "Waived"
            }
        }
    }

    let id: UUID
    var studioId: UUID
    var bookingId: UUID?
    var kind: Kind
    var amount: Int
    var currency: String
    var note: String?
    var createdAt: Date
}

struct Dispute: Codable, Identifiable, Hashable {
    let id: UUID
    var bookingId: UUID
    var openedBy: UUID
    var reason: String
    var status: ReportStatus
    var createdAt: Date
}

/// GDPR data export (art. 15 / 20).
struct PersonalDataExport: Encodable {
    var notice = "This file contains the personal data EasySesh holds about you. Card numbers are held by our payment provider (Stripe) and never stored by EasySesh."
    var exportedAt: Date
    var account: UserAccount
    var artistProfile: ArtistProfile?
    var studios: [Studio]
    var bookings: [Booking]
    var payments: [PaymentTransaction]
    var payouts: [Payout]
    var platformFees: [FeeLedgerEntry]
    var messagesSent: [ChatMessage]
    var reviewsWritten: [Review]
    var reportsMade: [Report]
    var notifications: [AppNotification]
}
