package com.easysesh.app.core

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Currency
import java.util.Locale

object Money {
    /** Formats minor units, e.g. 1500 EUR -> "€15", 1550 -> "€15.50". */
    fun format(minorUnits: Int, currency: String): String {
        val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault())
        runCatching { formatter.currency = Currency.getInstance(currency.uppercase()) }
        val isWhole = minorUnits % 100 == 0
        formatter.minimumFractionDigits = if (isWhole) 0 else 2
        formatter.maximumFractionDigits = if (isWhole) 0 else 2
        return formatter.format(BigDecimal(minorUnits).movePointLeft(2))
    }

    /** Parses user input like "15", "15.5" or "15,50" into minor units. */
    fun parse(text: String): Int? {
        val value = text.replace(",", ".").trim().toBigDecimalOrNull() ?: return null
        if (value < BigDecimal.ZERO) return null
        return value.movePointRight(2).setScale(0, RoundingMode.HALF_UP).toInt()
    }

    /** Integer percentage with half-up rounding. */
    fun percent(amount: Int, percent: Int): Int = (amount * percent + 50) / 100

    fun editableString(minorUnits: Int): String =
        if (minorUnits % 100 == 0) "${minorUnits / 100}" else String.format(Locale.US, "%.2f", minorUnits / 100.0)
}

object Distance {
    fun format(meters: Double, metric: Boolean = true): String {
        if (metric) {
            if (meters < 1000) return "${Math.round(meters / 10).toInt() * 10} m"
            return String.format(Locale.getDefault(), "%.1f km", meters / 1000)
        }
        return String.format(Locale.getDefault(), "%.1f mi", meters / 1609.344)
    }

    /** Great-circle distance in meters (same as CLLocation.distance). */
    fun meters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2).let { it * it } +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.sin(dLon / 2).let { it * it }
        return 2 * r * Math.asin(Math.min(1.0, Math.sqrt(a)))
    }
}

/** A point on the map (CLLocation stand-in). */
data class GeoPoint(val latitude: Double, val longitude: Double) {
    fun distanceTo(other: GeoPoint) = Distance.meters(latitude, longitude, other.latitude, other.longitude)
}

// Date helpers (device time zone, like iOS's Calendar.current).
val Instant.startOfDay: Instant get() = atZone(ZoneId.systemDefault()).toLocalDate().atStartOfDay(ZoneId.systemDefault()).toInstant()
fun Instant.addingMinutes(minutes: Int): Instant = plusSeconds(minutes * 60L)
fun Instant.addingHours(hours: Int): Instant = plusSeconds(hours * 3600L)
fun Instant.addingDays(days: Int): Instant = atZone(ZoneId.systemDefault()).plusDays(days.toLong()).toInstant()
fun Instant.toLocalDate(): LocalDate = atZone(ZoneId.systemDefault()).toLocalDate()
fun Instant.isSameDay(other: Instant) = toLocalDate() == other.toLocalDate()
fun Instant.hoursUntil(other: Instant) = ChronoUnit.SECONDS.between(this, other) / 3600.0
