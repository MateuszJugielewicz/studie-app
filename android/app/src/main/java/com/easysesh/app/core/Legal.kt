package com.easysesh.app.core

import android.content.Context
import com.easysesh.app.model.UserRole

/** Legal documents bundled with the app (source: /legal in the repository, copied by Gradle). */
enum class LegalDocument(val raw: String, val title: String, val symbol: String) {
    Terms("terms", "Terms & Conditions", "doc.text"),
    Privacy("privacy", "Privacy Policy", "hand.raised"),
    Cookies("cookies", "Cookie Policy", "internaldrive"),
    Refunds("refund-and-cancellation", "Refund & Cancellation Policy", "arrow.uturn.backward.circle"),
    StudioAgreement("studio-agreement", "Studio Agreement", "building.2"),
    CommunityGuidelines("community-guidelines", "Community Guidelines", "person.3");

    /** The document in the app's language (legal/<code>/<name>.md), falling back to English. */
    fun markdown(context: Context, language: String): String {
        val assets = context.assets
        if (language != "en") {
            runCatching { return assets.open("legal/$language/$raw.md").bufferedReader().use { it.readText() } }
        }
        return runCatching { assets.open("legal/$raw.md").bufferedReader().use { it.readText() } }
            .getOrElse { "# $title\n\nThis document could not be loaded. Find it in Settings → Support." }
    }

    companion object {
        /** Bump when a document changes materially; users must accept again. Same as iOS. */
        const val CURRENT_VERSION = "2026-09-26"

        /** Documents a user of the given role must accept. */
        fun required(role: UserRole) =
            if (role == UserRole.StudioOwner) listOf(Terms, Privacy, StudioAgreement) else listOf(Terms, Privacy)

        /** Terms versions are dates ("2026-09-25", optionally with a suffix), so they compare as text. */
        fun newest(a: String, b: String?): String = if (b != null && b > a) b else a
    }
}
