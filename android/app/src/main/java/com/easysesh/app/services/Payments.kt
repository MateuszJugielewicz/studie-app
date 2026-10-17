package com.easysesh.app.services

import com.easysesh.app.BuildConfig
import com.easysesh.app.data.BackendError
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.forms.submitForm
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Parameters
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Turns bank details typed in the app into a one-time Stripe token with the publishable key,
 * so the account number goes straight to Stripe and never through EasySesh's servers.
 */
object StripeBankTokenizer {
    private val http by lazy { HttpClient(OkHttp) }

    /** Letters and digits only, upper-cased ("dk50 0040 0440…" → "DK500040…"). */
    fun normalized(iban: String) = iban.uppercase().filter { (it.isLetterOrDigit()) && it.code < 128 }

    /** Standard IBAN checksum (mod 97), so typos are caught before asking Stripe. */
    fun isValidIban(iban: String): Boolean {
        val value = normalized(iban)
        if (value.length !in 15..34 || !value.take(2).all { it.isLetter() }) return false
        val rearranged = value.drop(4) + value.take(4)
        var remainder = 0
        for (character in rearranged) {
            val digits = if (character.isLetter()) (character.code - 55).toString() else character.toString()
            for (digit in digits) remainder = (remainder * 10 + (digit - '0')) % 97
        }
        return remainder == 1
    }

    fun currency(country: String) = when (country) {
        "DK" -> "dkk"
        "SE" -> "sek"
        "NO" -> "nok"
        "GB" -> "gbp"
        "PL" -> "pln"
        "CH" -> "chf"
        else -> "eur"
    }

    suspend fun token(iban: String, holder: String): String {
        val key = BuildConfig.STRIPE_PUBLISHABLE_KEY.ifEmpty { throw BackendError.Server("Stripe is not configured.") }
        val number = normalized(iban)
        val country = number.take(2)
        val response = http.submitForm(
            url = "https://api.stripe.com/v1/tokens",
            formParameters = Parameters.build {
                append("bank_account[country]", country)
                append("bank_account[currency]", currency(country))
                append("bank_account[account_number]", number)
                append("bank_account[account_holder_name]", holder)
            },
        ) { header("Authorization", "Bearer $key") }
        val json = Json.parseToJsonElement(response.bodyAsText()).jsonObject
        json["id"]?.jsonPrimitive?.content?.let { return it }
        val message = json["error"]?.jsonObject?.get("message")?.jsonPrimitive?.content
        throw BackendError.Validation(message ?: "Stripe couldn't read these bank details.")
    }
}
