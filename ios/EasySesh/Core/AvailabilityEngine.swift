import Foundation

struct TimeSlot: Hashable, Identifiable {
    var start: Date
    var end: Date
    var id: Date { start }
}

/// Computes bookable start times from opening hours, existing bookings and blocked periods.
struct AvailabilityEngine {
    /// Granularity of start times in minutes.
    var stepMinutes: Int = 60

    /// Opening hours are wall-clock times in the studio's own time zone.
    func studioCalendar(for studio: Studio) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = studio.timeZone
        return calendar
    }

    /// Opening window for the given day, or nil when closed.
    func openingWindow(for studio: Studio, on day: Date) -> DateInterval? {
        let calendar = studioCalendar(for: studio)
        let dayStart = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: dayStart)
        guard let hours = studio.hours(for: weekday), !hours.isClosed else { return nil }
        var closes = hours.closesAt
        if closes <= hours.opensAt { closes += 24 * 60 }
        guard let open = calendar.date(byAdding: .minute, value: hours.opensAt, to: dayStart),
              let close = calendar.date(byAdding: .minute, value: closes, to: dayStart) else { return nil }
        return DateInterval(start: open, end: close)
    }

    /// Available start slots of `hours` length on `day`.
    func availableSlots(
        for studio: Studio,
        on day: Date,
        hours: Int,
        busy: [DateInterval],
        now: Date = .now
    ) -> [TimeSlot] {
        guard hours > 0, let window = openingWindow(for: studio, on: day) else { return [] }
        let policy = studio.bookingPolicy
        let earliest = now.addingTimeInterval(TimeInterval(policy.minimumNoticeHours * 3600))
        let latestDay = studioCalendar(for: studio).startOfDay(for: now).addingTimeInterval(TimeInterval((policy.maxAdvanceDays + 1) * 86_400))
        guard window.start < latestDay else { return [] }

        let buffer = TimeInterval(policy.bufferMinutes * 60)
        let paddedBusy = busy.map { DateInterval(start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer)) }
        let duration = TimeInterval(hours * 3600)

        var slots: [TimeSlot] = []
        var start = window.start
        while start.addingTimeInterval(duration) <= window.end {
            let end = start.addingTimeInterval(duration)
            let candidate = DateInterval(start: start, end: end)
            let overlaps = paddedBusy.contains { Self.overlaps($0, candidate) }
            if start >= earliest && !overlaps {
                slots.append(TimeSlot(start: start, end: end))
            }
            start = start.addingTimeInterval(TimeInterval(stepMinutes * 60))
        }
        return slots
    }

    func isAvailable(_ studio: Studio, on day: Date, hours: Int, busy: [DateInterval], now: Date = .now) -> Bool {
        !availableSlots(for: studio, on: day, hours: hours, busy: busy, now: now).isEmpty
    }

    /// True when the interval fits the opening hours and does not clash. Used to validate reschedules.
    /// Checks the start's own day and the previous day (whose window may run past midnight).
    func canBook(_ studio: Studio, start: Date, hours: Int, busy: [DateInterval], now: Date = .now) -> Bool {
        [start, start.addingTimeInterval(-86_400)].contains { day in
            availableSlots(for: studio, on: day, hours: hours, busy: busy, now: now).contains { $0.start == start }
        }
    }

    /// Half-open overlap: touching intervals do not clash.
    static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }
}
