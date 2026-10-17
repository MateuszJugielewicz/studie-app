package com.easysesh.app.core

import com.easysesh.app.model.BookedAddOn
import com.easysesh.app.model.CancellationPolicy
import com.easysesh.app.model.PriceBreakdown
import com.easysesh.app.model.PriceUnit
import com.easysesh.app.model.ServiceAddOn
import com.easysesh.app.model.SessionType
import com.easysesh.app.model.Studio
import com.easysesh.app.model.UserRole
import java.time.Instant

/** Platform-wide commercial settings. Mirrored server-side in supabase/functions/_shared/pricing.ts. */
object PlatformConfig {
    /** Extra fee on top for the artist (none: artists pay the studio's price). */
    const val ARTIST_SERVICE_FEE_PERCENT = 0
    /** EasySesh takes 10% of every sale. Card: deducted from the studio payout. Cash: owed by the studio. */
    const val PLATFORM_FEE_PERCENT = 10
    /** Days after a completed session before the studio payout is released. */
    const val PAYOUT_DELAY_DAYS = 2
    const val MAX_SESSION_HOURS = 12
}

object PricingEngine {
    fun quote(studio: Studio, sessionType: SessionType, hours: Int, selected: Map<String, Int> = emptyMap()): PriceBreakdown {
        val h = maxOf(hours, 1)
        val sessionAmount = sessionType.hourlyRate * h
        var addOnsAmount = 0
        for (addOn in studio.addOns) {
            val quantity = selected[addOn.id] ?: continue
            if (quantity <= 0) continue
            addOnsAmount += amount(addOn, quantity, h)
        }
        val subtotal = sessionAmount + addOnsAmount
        val serviceFee = Money.percent(subtotal, PlatformConfig.ARTIST_SERVICE_FEE_PERCENT)
        val total = subtotal + serviceFee
        val depositPercent = studio.bookingPolicy.depositPercent.coerceIn(0, 100)
        val deposit = if (depositPercent in 1..99) Money.percent(subtotal, depositPercent) else 0
        val dueNow = if (deposit > 0) deposit + serviceFee else total
        val commission = Money.percent(subtotal, PlatformConfig.PLATFORM_FEE_PERCENT)
        return PriceBreakdown(
            currency = studio.currency, hourlyRate = sessionType.hourlyRate, hours = h,
            sessionAmount = sessionAmount, addOnsAmount = addOnsAmount, subtotal = subtotal,
            serviceFee = serviceFee, total = total, depositAmount = deposit, dueNow = dueNow,
            dueLater = total - dueNow, studioCommission = commission, studioPayout = subtotal - commission,
        )
    }

    fun amount(addOn: ServiceAddOn, quantity: Int, hours: Int): Int = when (addOn.unit) {
        PriceUnit.PerHour -> addOn.price * hours
        PriceUnit.PerSession -> addOn.price
        PriceUnit.PerTrack -> addOn.price * quantity
    }

    /** Cash is offered when the studio allows it and no card deposit is required. */
    fun acceptsCash(studio: Studio) = studio.bookingPolicy.acceptsCash && studio.bookingPolicy.depositPercent == 0

    fun bookedAddOns(studio: Studio, selected: Map<String, Int>, hours: Int): List<BookedAddOn> =
        studio.addOns.mapNotNull { addOn ->
            val quantity = selected[addOn.id] ?: return@mapNotNull null
            if (quantity <= 0) null else BookedAddOn(addOn.id, addOn.name, quantity, amount(addOn, quantity, hours))
        }
}

/** Decides how much an artist gets back when a booking is cancelled. */
object RefundCalculator {
    fun refundPercent(policy: CancellationPolicy, hoursUntilStart: Double): Int = when (policy) {
        CancellationPolicy.Flexible -> if (hoursUntilStart >= 24) 100 else 0
        CancellationPolicy.Moderate -> when {
            hoursUntilStart >= 72 -> 100
            hoursUntilStart >= 24 -> 50
            else -> 0
        }
        CancellationPolicy.Strict -> if (hoursUntilStart >= 24 * 7) 50 else 0
    }

    fun refundAmount(
        price: PriceBreakdown,
        amountPaid: Int,
        policy: CancellationPolicy,
        startsAt: Instant,
        cancelledBy: UserRole,
        now: Instant = Instant.now(),
    ): Int {
        if (amountPaid <= 0) return 0
        if (cancelledBy != UserRole.Artist) return amountPaid
        val percent = refundPercent(policy, now.hoursUntil(startsAt))
        if (percent == 100) return amountPaid
        // The service fee is only returned on full refunds.
        val refundableBase = maxOf(amountPaid - price.serviceFee, 0)
        return Money.percent(refundableBase, percent)
    }
}
