package com.easysesh.app.model

import com.easysesh.app.core.PgInstant
import com.easysesh.app.core.PlatformConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID

/** A studio listing (`studios` table). Nested value types are stored as jsonb. */
@Serializable
data class Studio(
    val id: String,
    val ownerId: String,
    val name: String = "",
    val tagline: String = "",
    val description: String = "",
    val photoUrls: List<String> = emptyList(),
    val videoUrl: String? = null,
    val address: StudioAddress = StudioAddress(),
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val contact: StudioContact = StudioContact(),
    val currency: String = "EUR",
    /** Lowest hourly rate across session types, in minor units. Kept in sync by `normalized()`. */
    val priceFrom: Int = 0,
    val sessionTypes: List<SessionType> = emptyList(),
    val addOns: List<ServiceAddOn> = emptyList(),
    val facilities: List<Facility> = emptyList(),
    val equipment: List<EquipmentItem> = emptyList(),
    val engineers: List<StudioPerson> = emptyList(),
    val capacity: Int = 4,
    val genres: List<Genre> = emptyList(),
    val openingHours: List<OpeningHours> = OpeningHours.standardWeek,
    val rules: List<String> = emptyList(),
    val bookingPolicy: BookingPolicy = BookingPolicy(),
    val status: StudioStatus = StudioStatus.Draft,
    val isActive: Boolean = false,
    val isVerified: Boolean = false,
    val adminNote: String? = null,
    val ratingAverage: Double = 0.0,
    val reviewCount: Int = 0,
    val bookingCount: Int = 0,
    val createdAt: PgInstant = Instant.now(),
    val submittedAt: PgInstant? = null,
    /** IANA time zone of the studio. Opening hours are interpreted in this zone. */
    val timezone: String? = null,
    /** Cosmetic "EasySesh team" badge (set by admins). */
    val hasAdminBadge: Boolean? = null,
    /** Special tags only admins can add, e.g. "Staff pick". */
    val adminTags: List<String>? = null,
    /** Paid or granted promotion: shown first in search with a "Promoted" tag until this date. */
    val promotedUntil: PgInstant? = null,
    /** Special deal: this studio's platform fee in percent (default 10). */
    val platformFeePercent: Int? = null,
) {
    val feePercent: Int get() = platformFeePercent ?: PlatformConfig.PLATFORM_FEE_PERCENT
    val isPromoted: Boolean get() = (promotedUntil ?: Instant.MIN).isAfter(Instant.now())
    val showsAdminBadge: Boolean get() = hasAdminBadge == true
    val specialTags: List<String> get() = adminTags ?: emptyList()
    val zoneId: ZoneId get() = timezone?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.systemDefault()

    /** Visible to artists only when approved by an admin and switched on. */
    val isBookable: Boolean get() = status == StudioStatus.Approved && isActive
    val microphones: List<EquipmentItem> get() = equipment.filter { it.category == EquipmentCategory.Microphone }
    val offersMixing: Boolean get() = addOns.any { it.kind == AddOnKind.Mixing }
    val offersMastering: Boolean get() = addOns.any { it.kind == AddOnKind.Mastering }

    fun sessionType(id: String) = sessionTypes.firstOrNull { it.id == id }
    fun hours(weekday: Int) = openingHours.firstOrNull { it.weekday == weekday }

    /** Recomputes derived fields before saving. */
    fun normalized() = copy(priceFrom = sessionTypes.minOfOrNull { it.hourlyRate } ?: 0)

    companion object {
        fun newDraft(ownerId: String) = Studio(
            id = UUID.randomUUID().toString(),
            ownerId = ownerId,
            sessionTypes = listOf(SessionType("recording", "Recording", "", 3000, 2, false)),
        )
    }
}

@Serializable
data class StudioAddress(
    val street: String = "",
    val postalCode: String = "",
    val city: String = "",
    /** Neighbourhood / area shown publicly, e.g. "Exarchia". */
    val area: String = "",
    val country: String = "",
) {
    val singleLine: String
        get() = listOf(street, listOf(postalCode, city).filter { it.isNotEmpty() }.joinToString(" "), country)
            .filter { it.isNotEmpty() }.joinToString(", ")
    val publicArea: String get() = listOf(area, city).filter { it.isNotEmpty() }.joinToString(", ")
}

@Serializable
data class StudioContact(val phone: String = "", val email: String = "", val website: String = "")

@Serializable
data class SessionType(
    val id: String,
    val name: String,
    val details: String = "",
    /** Price per hour in minor units (cents). */
    val hourlyRate: Int,
    val minimumHours: Int = 1,
    val includesEngineer: Boolean = false,
)

@Serializable
enum class AddOnKind(val title: String) {
    @SerialName("engineer") Engineer("Engineer"),
    @SerialName("producer") Producer("Producer"),
    @SerialName("mixing") Mixing("Mixing"),
    @SerialName("mastering") Mastering("Mastering"),
    @SerialName("other") Other("Extra"),
}

@Serializable
enum class PriceUnit(val suffix: String) {
    @SerialName("per_hour") PerHour("/ hour"),
    @SerialName("per_session") PerSession("/ session"),
    @SerialName("per_track") PerTrack("/ track"),
}

@Serializable
data class ServiceAddOn(val id: String, val kind: AddOnKind, val name: String, val price: Int, val unit: PriceUnit)

@Serializable
data class EquipmentItem(val id: String, val category: EquipmentCategory, val name: String)

@Serializable
data class StudioPerson(val id: String, val name: String, val role: String = "", val bio: String = "")

/**
 * `weekday` follows iOS `Calendar.component(.weekday)`: 1 = Sunday … 7 = Saturday.
 * Times are minutes after midnight. `closesAt` may exceed 1440 for studios open past midnight.
 */
@Serializable
data class OpeningHours(val weekday: Int, val isClosed: Boolean, val opensAt: Int, val closesAt: Int) {
    val id: Int get() = weekday

    val weekdayName: String get() = dayOfWeek(weekday).getDisplayName(TextStyle.FULL, Locale.getDefault())
        .replaceFirstChar { it.titlecase(Locale.getDefault()) }

    val label: String get() = if (isClosed) "Closed" else "${format(opensAt)} – ${format(closesAt)}"

    companion object {
        fun format(minutes: Int): String {
            val m = minutes % (24 * 60)
            return "%02d:%02d".format(m / 60, m % 60)
        }

        /** Monday-first ordering for display. */
        val displayOrder = listOf(2, 3, 4, 5, 6, 7, 1)

        val standardWeek: List<OpeningHours> get() = (1..7).map { OpeningHours(it, false, 10 * 60, 22 * 60) }

        /** iOS weekday (1 = Sunday) → java.time. */
        fun dayOfWeek(weekday: Int): DayOfWeek = if (weekday == 1) DayOfWeek.SUNDAY else DayOfWeek.of(weekday - 1)
        fun weekday(day: DayOfWeek): Int = if (day == DayOfWeek.SUNDAY) 1 else day.value + 1
    }
}

@Serializable
data class BookingPolicy(
    /** When false the studio must accept each request (card is authorised, charged on acceptance). */
    val instantBook: Boolean = true,
    val cancellationPolicy: CancellationPolicy = CancellationPolicy.Moderate,
    /** 0 = full payment up front. Otherwise the percentage of the subtotal charged at booking. */
    val depositPercent: Int = 0,
    val minimumNoticeHours: Int = 12,
    val maxAdvanceDays: Int = 90,
    val bufferMinutes: Int = 0,
    val terms: String = "",
    /** Artists may choose to pay cash at the session (only without a card deposit). */
    val acceptsCash: Boolean = true,
    /** Artists can check in when they arrive (recommended against fraud). */
    val checkInEnabled: Boolean = true,
)

/** Private payout details (`studio_payout_accounts` table, owner + admin only). */
@Serializable
data class PayoutAccount(
    val studioId: String,
    val accountHolder: String = "",
    val ibanLast4: String = "",
    val stripeAccountId: String? = null,
    val payoutsEnabled: Boolean = false,
)

/** A studio-blocked period (maintenance, private use, etc.). */
@Serializable
data class BlockedSlot(
    val id: String,
    val studioId: String,
    val startsAt: PgInstant,
    val endsAt: PgInstant,
    val reason: String = "",
) {
    val interval: Interval get() = Interval(startsAt, maxOf(startsAt, endsAt))
}

/** Half-open time interval (like Foundation's DateInterval). */
data class Interval(val start: Instant, val end: Instant) {
    fun contains(instant: Instant) = !instant.isBefore(start) && !instant.isAfter(end)
}
