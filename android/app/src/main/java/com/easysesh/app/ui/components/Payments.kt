package com.easysesh.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import com.easysesh.app.BuildConfig
import com.easysesh.app.data.BackendError
import com.easysesh.app.data.PaymentIntentInfo
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.rememberPaymentSheet
import kotlinx.coroutines.CompletableDeferred

enum class PaymentOutcome { Completed, Cancelled }

/**
 * Presents Stripe PaymentSheet for a PaymentIntent created by the `create-payment-intent` edge
 * function: Google Pay plus every method turned on in the Stripe dashboard that works for the amount,
 * currency and country (cards, Link, PayPal, Klarna, MobilePay, iDEAL, …). Methods that settle days
 * later (SEPA Debit, bank transfers) are left out, because a booking needs to know right away whether
 * it's paid. The Android counterpart of StripePaymentProcessor on iOS.
 */
class PaymentLauncher(private val sheet: PaymentSheet?) {
    private var pending: CompletableDeferred<PaymentSheetResult>? = null

    val isAvailable get() = sheet != null

    fun onResult(result: PaymentSheetResult) {
        pending?.complete(result)
        pending = null
    }

    suspend fun pay(info: PaymentIntentInfo): PaymentOutcome {
        val sheet = sheet ?: throw BackendError.PaymentFailed("Stripe is not configured.")
        val deferred = CompletableDeferred<PaymentSheetResult>()
        pending = deferred
        val live = BuildConfig.STRIPE_PUBLISHABLE_KEY.startsWith("pk_live")
        val builder = PaymentSheet.Configuration.Builder("EasySesh")
            .allowsDelayedPaymentMethods(false)
        if (BuildConfig.GOOGLE_PAY_ENABLED) {
            builder.googlePay(
                PaymentSheet.GooglePayConfiguration(
                    environment = if (live) PaymentSheet.GooglePayConfiguration.Environment.Production else PaymentSheet.GooglePayConfiguration.Environment.Test,
                    countryCode = BuildConfig.MERCHANT_COUNTRY,
                    currencyCode = info.currency.uppercase(),
                ),
            )
        }
        if (info.customerId != null && info.ephemeralKey != null) {
            builder.customer(PaymentSheet.CustomerConfiguration(info.customerId, info.ephemeralKey))
        }
        sheet.presentWithPaymentIntent(info.clientSecret, builder.build())
        return when (val result = deferred.await()) {
            is PaymentSheetResult.Completed -> PaymentOutcome.Completed
            is PaymentSheetResult.Canceled -> PaymentOutcome.Cancelled
            is PaymentSheetResult.Failed -> throw BackendError.PaymentFailed(result.error.localizedMessage ?: "Payment failed")
        }
    }
}

val LocalPaymentLauncher = staticCompositionLocalOf { PaymentLauncher(null) }

/** Provides the payment sheet to everything inside (created once per activity). */
@Composable
fun PaymentProvider(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val key = BuildConfig.STRIPE_PUBLISHABLE_KEY
    if (key.isEmpty()) {
        content()
        return
    }
    remember { PaymentConfiguration.init(context, key) }
    val holder = remember { arrayOfNulls<PaymentLauncher>(1) }
    val sheet = rememberPaymentSheet { result -> holder[0]?.onResult(result) }
    val launcher = remember(sheet) { PaymentLauncher(sheet).also { holder[0] = it } }
    CompositionLocalProvider(LocalPaymentLauncher provides launcher) { content() }
}
