import Foundation

enum EarningsCalculator {
    static func summary(bookings: [Booking], payouts: [Payout], currency: String, now: Date = .now, calendar: Calendar = .current) -> EarningsSummary {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now.startOfDay
        let completed = bookings.filter { $0.status == .completed }
        let thisMonth = completed.filter { $0.endsAt >= monthStart }

        let monthly: [MonthlyAmount] = (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: monthStart),
                  let range = calendar.dateInterval(of: .month, for: month) else { return nil }
            let amount = completed.filter { range.contains($0.endsAt) }.reduce(0) { $0 + $1.price.studioPayout }
            return MonthlyAmount(month: range.start, amount: amount)
        }

        return EarningsSummary(
            currency: currency,
            grossThisMonth: thisMonth.reduce(0) { $0 + $1.price.subtotal },
            netThisMonth: thisMonth.reduce(0) { $0 + $1.price.studioPayout },
            netAllTime: completed.reduce(0) { $0 + $1.price.studioPayout },
            pendingPayout: payouts.filter { $0.status == .scheduled || $0.status == .inTransit }.reduce(0) { $0 + $1.amount },
            completedSessions: completed.count,
            upcomingSessions: bookings.filter { $0.isUpcoming }.count,
            hoursBooked: completed.reduce(0) { $0 + $1.hours },
            monthly: monthly
        )
    }
}
