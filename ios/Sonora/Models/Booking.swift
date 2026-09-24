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

    var platformRevenue: Int { serviceFee + studioCommission }
}

/// Input for creating a booking.
struct BookingRequest: Hashable {
    var studio: Studio
    var sessionType: SessionType
    var startsAt: Date
    var hours: Int
    var addOns: [String: Int]
    var notes: String
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

/// Platform fees a studio owes Sonora for cash bookings, and how they were settled.
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
