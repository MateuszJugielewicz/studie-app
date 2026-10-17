package com.easysesh.app.data

import com.easysesh.app.core.L10n
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Same cases and messages as the iOS app's BackendError. */
sealed class BackendError(message: String) : Exception(message) {
    data object NotAuthenticated : BackendError("Please sign in to continue.")
    data object NotFound : BackendError("We couldn't find that.")
    data object Forbidden : BackendError("You don't have access to this.")
    data object AccountSuspended : BackendError("This account is suspended. Contact support.")
    /** Suspended or banned by the EasySesh team, possibly for a limited period. */
    class AccountRestricted(val banned: Boolean, val until: Instant?, val reason: String?) : BackendError(restrictionMessage(banned, until, reason))
    data object InvalidCredentials : BackendError("Wrong email or password.")
    data object EmailInUse : BackendError("An account with this email already exists.")
    data object SlotUnavailable : BackendError("That time is no longer available. Please pick another slot.")
    class Validation(val text: String) : BackendError(text)
    class PaymentFailed(val text: String) : BackendError("Payment failed: $text")
    class Server(val text: String) : BackendError(text)

    companion object {
        fun restrictionMessage(banned: Boolean, until: Instant?, reason: String?): String {
            val parts = mutableListOf(if (banned) L10n.tr("This account is banned.") else L10n.tr("This account is suspended."))
            if (until != null) {
                val date = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                    .withLocale(L10n.locale()).format(until.atZone(ZoneId.systemDefault()))
                parts += L10n.format("Until %@.", date)
            } else {
                parts += L10n.tr("Contact support if you think this is a mistake.")
            }
            if (!reason.isNullOrEmpty()) parts += L10n.format("Reason: %@", reason)
            return parts.joinToString(" ")
        }
    }
}

/** The text to show for any error, translated (like `error.userMessage` on iOS). */
val Throwable.userMessage: String
    get() = when (this) {
        is kotlinx.coroutines.CancellationException -> ""
        is BackendError.AccountRestricted -> message ?: ""
        is BackendError.PaymentFailed -> L10n.format("Payment failed: %@", L10n.tr(text))
        is BackendError -> L10n.tr(message ?: "")
        else -> L10n.tr(message ?: "Something went wrong. Please try again.")
    }
