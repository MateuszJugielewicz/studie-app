package com.easysesh.app.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit

/** The iOS app's `.formatted(...)` date styles, in the app's language. */
object Dates {
    private val zone get() = ZoneId.systemDefault()
    private fun fmt(f: DateTimeFormatter, i: Instant, zone: ZoneId = this.zone) = f.withLocale(L10n.locale()).format(i.atZone(zone))

    /** "17 Oct 2026" (date: .abbreviated). */
    fun abbreviated(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM), i, zone)
    /** "17 Oct 2026, 14:00" (date: .abbreviated, time: .shortened). */
    fun abbreviatedWithTime(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT), i, zone)
    /** "14:00" (time: .shortened). */
    fun time(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT), i, zone)
    /** "Friday, 17 October" (weekday wide + day + month). */
    fun weekdayDayMonth(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("EEEE d MMMM"), i, zone).replaceFirstChar { it.titlecase(L10n.locale()) }
    /** "Fri 17" (weekday abbreviated + day). */
    fun weekdayShortDay(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("EEE d"), i, zone).replaceFirstChar { it.titlecase(L10n.locale()) }
    /** "Fri" */
    fun weekdayShort(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("EEE"), i, zone).replaceFirstChar { it.titlecase(L10n.locale()) }
    /** "17" */
    fun day(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("d"), i, zone)
    /** "Oct" */
    fun monthShort(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("MMM"), i, zone)
    /** "October 2026" */
    fun monthYear(i: Instant, zone: ZoneId = this.zone) = fmt(DateTimeFormatter.ofPattern("LLLL yyyy"), i, zone).replaceFirstChar { it.titlecase(L10n.locale()) }
    /** "2026-10-17" */
    fun iso(i: Instant) = DateTimeFormatter.ISO_LOCAL_DATE.format(i.atZone(zone))

    fun weekdayName(date: LocalDate) = date.dayOfWeek.getDisplayName(TextStyle.FULL, L10n.locale()).replaceFirstChar { it.titlecase(L10n.locale()) }

    /** "5 minutes ago", "yesterday" (iOS .relative(presentation: .named)). */
    fun relative(i: Instant, now: Instant = Instant.now()): String {
        val seconds = ChronoUnit.SECONDS.between(i, now)
        val locale = L10n.locale()
        return when {
            seconds < 60 -> L10n.tr("now")
            seconds < 3600 -> android.text.format.DateUtils.getRelativeTimeSpanString(i.toEpochMilli(), now.toEpochMilli(), android.text.format.DateUtils.MINUTE_IN_MILLIS).toString()
            seconds < 86_400 -> android.text.format.DateUtils.getRelativeTimeSpanString(i.toEpochMilli(), now.toEpochMilli(), android.text.format.DateUtils.HOUR_IN_MILLIS).toString()
            else -> android.text.format.DateUtils.getRelativeTimeSpanString(i.toEpochMilli(), now.toEpochMilli(), android.text.format.DateUtils.DAY_IN_MILLIS).toString()
        }.also { locale.hashCode() }
    }
}
