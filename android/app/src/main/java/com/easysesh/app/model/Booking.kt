package com.easysesh.app.model

import com.easysesh.app.core.PgInstant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

@Serializable
data class Booking(
    val id: String,
    val reference: String = "",
    val artistId: String,
    val studioId: String,
    val artistName: String = "",
    val studioName: String = "",
    val sessionTypeId: String = "",
    val sessionTypeName: String = "",
    val startsAt: PgInstant,
    val endsAt: PgInstant,
    val hours: Int = 1,
    val addOns: List<BookedAddOn> = emptyList(),
    val status: BookingStatus,
    val paymentStatus: PaymentStatus = PaymentStatus.Unpaid,
    val price: PriceBreakdown,
    val notes: String = "",
    val cancellationReason: String? = null,
    val cancelledBy: UserRole? = null,
    val refundAmount: Int = 0,
    val hasReview: Boolean = false,
    val createdAt: PgInstant = Instant.EPOCH,
    val updatedAt: PgInstant = Instant.EPOCH,
    val paymentMethod: PaymentMethod? = null,
    val cashReceivedAt: PgInstant? = null,
    /** Check-in on arrival (optional, recommended): when the artist checked in and how far away. */
    val artistCheckedInAt: PgInstant? = null,
    val artistCheckInDistanceM: Int? = null,
    val studioConfirmedArrivalAt: PgInstant? = null,
) {
    /** Check-in opens 1 hour before the session and closes when it ends. */
    fun canCheckIn(now: Instant = Instant.now()) =
        status == BookingStatus.Confirmed && artistCheckedInAt == null &&
            !now.isBefore(startsAt.minusSeconds(3600)) && !now.isAfter(endsAt)

    val isCash get() = paymentMethod == PaymentMethod.Cash
    val interval get() = Interval(startsAt, endsAt)
    val isUpcoming get() = endsAt.isAfter(Instant.now()) && status.isActive
    val canCancel get() = status.isActive && startsAt.isAfter(Instant.now())
    val canReschedule get() = status == BookingStatus.Confirmed && startsAt.isAfter(Instant.now())
    val canReview get() = status == BookingStatus.Completed && !hasReview
}

@Serializable
data class BookedAddOn(val id: String, val name: String, val quantity: Int, val amount: Int)

/** Every amount is in minor units of `currency`. */
@Serializable
data class PriceBreakdown(
    val currency: String,
    val hourlyRate: Int,
    val hours: Int,
    val sessionAmount: Int,
    val addOnsAmount: Int,
    /** session + add-ons: what the studio charges. */
    val subtotal: Int,
    /** Platform fee paid by the artist on top of the subtotal. */
    val serviceFee: Int,
    val total: Int,
    /** Share of the subtotal charged at booking when the studio requires a deposit (0 when paying in full). */
    val depositAmount: Int,
    val dueNow: Int,
    val dueLater: Int,
    /** Commission the platform keeps from the studio. */
    val studioCommission: Int,
    val studioPayout: Int,
    /** Discounts, computed by the server (studio offers and promo codes). An EasySesh promo code is
     *  paid by EasySesh and stored as a negative [serviceFee]. */
    val originalSubtotal: Int? = null,
    val offerDiscount: Int? = null,
    val promoDiscount: Int? = null,
    val promoCode: String? = null,
    val discounts: List<PriceDiscount> = emptyList(),
) {
    val platformRevenue get() = serviceFee + studioCommission
}

@Serializable
data class PriceDiscount(
    val label: String,
    val percent: Int,
    val amount: Int,
    /** "offer", "studio_code" or "easysesh_code". */
    val kind: String,
)

/** A studio's automatic deal, e.g. "Mixing 50% off". */
@Serializable
data class StudioOffer(
    val id: String,
    val studioId: String,
    val title: String,
    val percentOff: Int,
    /** everything | sessions | add_ons | session_type | add_on */
    val appliesTo: String = "everything",
    val targetId: String? = null,
    val endsAt: PgInstant? = null,
    val isActive: Boolean = true,
) {
    val isLive get() = isActive && (endsAt?.isAfter(Instant.now()) ?: true)
}

/** A code artists type in at checkout. [studioId] null = an EasySesh code (made by an admin). */
@Serializable
data class PromoCode(
    val id: String,
    val studioId: String? = null,
    val code: String,
    val percentOff: Int,
    val description: String = "",
    val endsAt: PgInstant? = null,
    val maxUses: Int? = null,
    val maxUsesPerUser: Int = 1,
    val isActive: Boolean = true,
    /** Bookings that used it (from `promo_code_usage`; not a column). */
    @kotlinx.serialization.Transient val uses: Int = 0,
)

/** Result of checking a promo code at checkout. */
@Serializable
data class PromoCheck(val code: String, val percentOff: Int, val description: String = "", val byEasysesh: Boolean = false)

/** Input for creating a booking. */
data class BookingRequest(
    val studio: Studio,
    val sessionType: SessionType,
    val startsAt: Instant,
    val hours: Int,
    val addOns: Map<String, Int>,
    val notes: String,
    val promoCode: String? = null,
)

/** A payment-side movement of money (`transactions` table). */
@Serializable
data class PaymentTransaction(
    val id: String,
    val bookingId: String,
    val studioId: String,
    val artistId: String,
    val kind: TransactionKind,
    val method: PaymentMethod,
    val status: TransactionStatus,
    val amount: Int,
    val platformFee: Int = 0,
    val currency: String,
    val receiptNumber: String = "",
    val cardBrand: String? = null,
    val cardLast4: String? = null,
    val failureReason: String? = null,
    val providerReference: String? = null,
    val createdAt: PgInstant,
)

@Serializable
data class Payout(
    val id: String,
    val studioId: String,
    val amount: Int,
    val currency: String,
    val status: PayoutStatus,
    val scheduledFor: PgInstant,
    val paidAt: PgInstant? = null,
    val bookingIds: List<String> = emptyList(),
)

data class EarningsSummary(
    val currency: String,
    val grossThisMonth: Int,
    val netThisMonth: Int,
    val netAllTime: Int,
    val pendingPayout: Int,
    val completedSessions: Int,
    val upcomingSessions: Int,
    val hoursBooked: Int,
    /** Net per calendar month, oldest first (last 6 months). */
    val monthly: List<MonthlyAmount>,
)

data class MonthlyAmount(val month: Instant, val amount: Int)

/** Platform fees a studio owes EasySesh for cash bookings, and how they were settled. */
@Serializable
data class FeeLedgerEntry(
    val id: String,
    val studioId: String,
    val bookingId: String? = null,
    val kind: Kind,
    val amount: Int,
    val currency: String,
    val note: String? = null,
    val createdAt: PgInstant,
) {
    @Serializable
    enum class Kind(val title: String) {
        @SerialName("cash_commission") CashCommission("Platform fee (cash booking)"),
        @SerialName("payout_offset") PayoutOffset("Deducted from payout"),
        @SerialName("invoice_payment") InvoicePayment("Invoice paid"),
        @SerialName("manual_payment") ManualPayment("Payment received"),
        @SerialName("waiver") Waiver("Waived"),
    }
}

@Serializable
data class Dispute(
    val id: String,
    val bookingId: String,
    val openedBy: String,
    val reason: String,
    val status: ReportStatus,
    val createdAt: PgInstant,
)
