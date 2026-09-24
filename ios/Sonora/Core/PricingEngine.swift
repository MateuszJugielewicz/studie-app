import Foundation

/// Platform-wide commercial settings. Mirrored server-side in `supabase/functions/_shared/pricing.ts`,
/// which is the source of truth for anything that is actually charged.
enum PlatformConfig {
    /// Service fee added on top for the artist.
    static let artistServiceFeePercent = 8
    /// Commission deducted from the studio's payout.
    static let studioCommissionPercent = 5
    /// Days after a completed session before the studio payout is released.
    static let payoutDelayDays = 2
    static let maxSessionHours = 12
}

enum PricingEngine {
    static func quote(
        studio: Studio,
        sessionType: SessionType,
        hours: Int,
        addOns selected: [String: Int] = [:]
    ) -> PriceBreakdown {
        let hours = max(hours, 1)
        let sessionAmount = sessionType.hourlyRate * hours

        var addOnsAmount = 0
        for addOn in studio.addOns {
            guard let quantity = selected[addOn.id], quantity > 0 else { continue }
            addOnsAmount += amount(for: addOn, quantity: quantity, hours: hours)
        }

        let subtotal = sessionAmount + addOnsAmount
        let serviceFee = Money.percent(subtotal, PlatformConfig.artistServiceFeePercent)
        let total = subtotal + serviceFee

        let depositPercent = min(max(studio.bookingPolicy.depositPercent, 0), 100)
        let deposit = depositPercent > 0 && depositPercent < 100 ? Money.percent(subtotal, depositPercent) : 0
        let dueNow = deposit > 0 ? deposit + serviceFee : total

        let commission = Money.percent(subtotal, PlatformConfig.studioCommissionPercent)

        return PriceBreakdown(
            currency: studio.currency,
            hourlyRate: sessionType.hourlyRate,
            hours: hours,
            sessionAmount: sessionAmount,
            addOnsAmount: addOnsAmount,
            subtotal: subtotal,
            serviceFee: serviceFee,
            total: total,
            depositAmount: deposit,
            dueNow: dueNow,
            dueLater: total - dueNow,
            studioCommission: commission,
            studioPayout: subtotal - commission
        )
    }

    static func amount(for addOn: ServiceAddOn, quantity: Int, hours: Int) -> Int {
        switch addOn.unit {
        case .perHour: addOn.price * hours
        case .perSession: addOn.price
        case .perTrack: addOn.price * quantity
        }
    }

    static func bookedAddOns(studio: Studio, selected: [String: Int], hours: Int) -> [BookedAddOn] {
        studio.addOns.compactMap { addOn in
            guard let quantity = selected[addOn.id], quantity > 0 else { return nil }
            return BookedAddOn(id: addOn.id, name: addOn.name, quantity: quantity, amount: amount(for: addOn, quantity: quantity, hours: hours))
        }
    }
}

/// Decides how much an artist gets back when a booking is cancelled.
enum RefundCalculator {
    /// Share of the refundable amount (0–100) for an artist-initiated cancellation.
    static func refundPercent(policy: CancellationPolicy, hoursUntilStart: Double) -> Int {
        switch policy {
        case .flexible:
            return hoursUntilStart >= 24 ? 100 : 0
        case .moderate:
            if hoursUntilStart >= 72 { return 100 }
            if hoursUntilStart >= 24 { return 50 }
            return 0
        case .strict:
            return hoursUntilStart >= 24 * 7 ? 50 : 0
        }
    }

    /// Amount to refund in minor units.
    /// - Parameters:
    ///   - amountPaid: What the artist has actually been charged so far.
    ///   - cancelledBy: A studio cancellation or decline always refunds everything.
    static func refundAmount(
        price: PriceBreakdown,
        amountPaid: Int,
        policy: CancellationPolicy,
        startsAt: Date,
        cancelledBy: UserRole,
        now: Date = .now
    ) -> Int {
        guard amountPaid > 0 else { return 0 }
        if cancelledBy != .artist { return amountPaid }

        let hours = startsAt.timeIntervalSince(now) / 3600
        let percent = refundPercent(policy: policy, hoursUntilStart: hours)
        if percent == 100 { return amountPaid }
        // The service fee is only returned on full refunds.
        let refundableBase = max(amountPaid - price.serviceFee, 0)
        return Money.percent(refundableBase, percent)
    }
}
