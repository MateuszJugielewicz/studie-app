package com.easysesh.app.core

import com.easysesh.app.model.Booking
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.EarningsSummary
import com.easysesh.app.model.MonthlyAmount
import com.easysesh.app.model.Payout
import com.easysesh.app.model.PayoutStatus
import com.easysesh.app.model.Studio
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

object StudioValidator {
    private val email = Regex("""^[^@\s]+@[^@\s]+\.[^@\s]+$""")

    /** Human-readable problems that block submission for review (English keys). */
    fun problems(studio: Studio): List<String> {
        val problems = mutableListOf<String>()
        if (studio.name.trim().length < 3) problems += "Add your studio's name."
        if (studio.description.length < 40) problems += "Write a description of at least 40 characters."
        if (studio.photoUrls.isEmpty()) problems += "Add at least one photo."
        if (studio.address.street.isEmpty() || studio.address.city.isEmpty()) problems += "Add the studio's address."
        if (studio.latitude == 0.0 && studio.longitude == 0.0) problems += "Place your studio on the map."
        if (!email.matches(studio.contact.email.trim())) problems += "Add a valid email address."
        if (studio.contact.phone.count { it.isDigit() } < 6) problems += "Add a phone number."
        if (studio.sessionTypes.isEmpty() || studio.sessionTypes.any { it.hourlyRate <= 0 }) problems += "Set a price for each session type."
        if (studio.openingHours.all { it.isClosed }) problems += "Set your opening hours."
        if (studio.genres.isEmpty()) problems += "Pick at least one genre."
        return problems
    }
}

object PasswordPolicy {
    const val MINIMUM_LENGTH = 10
    val hint: String get() = L10n.format("At least %lld characters with upper- and lowercase letters and a number.", MINIMUM_LENGTH)

    fun problem(password: String): String? {
        val ok = password.length >= MINIMUM_LENGTH && password.any { it.isUpperCase() } &&
            password.any { it.isLowerCase() } && password.any { it.isDigit() }
        return if (ok) null else hint
    }
}

object EarningsCalculator {
    fun summary(bookings: List<Booking>, payouts: List<Payout>, currency: String, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): EarningsSummary {
        val thisMonth = YearMonth.from(now.atZone(zone))
        val monthStart = thisMonth.atDay(1).atStartOfDay(zone).toInstant()
        val completed = bookings.filter { it.status == BookingStatus.Completed }
        val inMonth = completed.filter { !it.endsAt.isBefore(monthStart) }
        val monthly = (5 downTo 0).map { offset ->
            val month = thisMonth.minusMonths(offset.toLong())
            val start = month.atDay(1).atStartOfDay(zone).toInstant()
            val end = month.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
            MonthlyAmount(start, completed.filter { !it.endsAt.isBefore(start) && it.endsAt.isBefore(end) }.sumOf { it.price.studioPayout })
        }
        return EarningsSummary(
            currency = currency,
            grossThisMonth = inMonth.sumOf { it.price.subtotal },
            netThisMonth = inMonth.sumOf { it.price.studioPayout },
            netAllTime = completed.sumOf { it.price.studioPayout },
            pendingPayout = payouts.filter { it.status == PayoutStatus.Scheduled || it.status == PayoutStatus.InTransit }.sumOf { it.amount },
            completedSessions = completed.size,
            upcomingSessions = bookings.count { it.isUpcoming },
            hoursBooked = completed.sumOf { it.hours },
            monthly = monthly,
        )
    }
}
