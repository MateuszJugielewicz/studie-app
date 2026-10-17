package com.easysesh.app.core

import com.easysesh.app.model.Interval
import com.easysesh.app.model.OpeningHours
import com.easysesh.app.model.Studio
import java.time.Instant
import java.time.LocalDate

data class TimeSlot(val start: Instant, val end: Instant) {
    val id: Instant get() = start
}

/** Computes bookable start times from opening hours, existing bookings and blocked periods. */
class AvailabilityEngine(private val stepMinutes: Int = 60) {
    /** Opening window for the given day (in the studio's own time zone), or null when closed. */
    fun openingWindow(studio: Studio, day: Instant): Interval? {
        val zone = studio.zoneId
        val date: LocalDate = day.atZone(zone).toLocalDate()
        val dayStart = date.atStartOfDay(zone)
        val hours = studio.hours(OpeningHours.weekday(date.dayOfWeek)) ?: return null
        if (hours.isClosed) return null
        var closes = hours.closesAt
        if (closes <= hours.opensAt) closes += 24 * 60
        return Interval(dayStart.plusMinutes(hours.opensAt.toLong()).toInstant(), dayStart.plusMinutes(closes.toLong()).toInstant())
    }

    /** Available start slots of `hours` length on `day`. */
    fun availableSlots(studio: Studio, day: Instant, hours: Int, busy: List<Interval>, now: Instant = Instant.now()): List<TimeSlot> {
        if (hours <= 0) return emptyList()
        val window = openingWindow(studio, day) ?: return emptyList()
        val policy = studio.bookingPolicy
        val earliest = now.plusSeconds(policy.minimumNoticeHours * 3600L)
        val latestDay = now.atZone(studio.zoneId).toLocalDate().atStartOfDay(studio.zoneId).toInstant()
            .plusSeconds((policy.maxAdvanceDays + 1) * 86_400L)
        if (!window.start.isBefore(latestDay)) return emptyList()

        val buffer = policy.bufferMinutes * 60L
        val padded = busy.map { Interval(it.start.minusSeconds(buffer), it.end.plusSeconds(buffer)) }
        val duration = hours * 3600L
        val slots = mutableListOf<TimeSlot>()
        var start = window.start
        while (!start.plusSeconds(duration).isAfter(window.end)) {
            val end = start.plusSeconds(duration)
            val candidate = Interval(start, end)
            val clash = padded.any { overlaps(it, candidate) }
            if (!start.isBefore(earliest) && !clash) slots += TimeSlot(start, end)
            start = start.plusSeconds(stepMinutes * 60L)
        }
        return slots
    }

    fun isAvailable(studio: Studio, day: Instant, hours: Int, busy: List<Interval>, now: Instant = Instant.now()) =
        availableSlots(studio, day, hours, busy, now).isNotEmpty()

    /** True when the interval fits the opening hours and does not clash. Checks the start's day and the previous day. */
    fun canBook(studio: Studio, start: Instant, hours: Int, busy: List<Interval>, now: Instant = Instant.now()) =
        listOf(start, start.minusSeconds(86_400)).any { day ->
            availableSlots(studio, day, hours, busy, now).any { it.start == start }
        }

    companion object {
        /** Half-open overlap: touching intervals do not clash. */
        fun overlaps(a: Interval, b: Interval) = a.start.isBefore(b.end) && b.start.isBefore(a.end)
    }
}
