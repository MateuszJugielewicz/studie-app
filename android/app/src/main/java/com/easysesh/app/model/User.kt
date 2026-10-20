package com.easysesh.app.model

import com.easysesh.app.core.PgInstant
import kotlinx.serialization.Serializable
import java.net.URLEncoder
import java.time.Instant

/** The account row (`profiles` table). One per auth user. */
@Serializable
data class UserAccount(
    val id: String,
    val email: String,
    val role: UserRole,
    val status: AccountStatus = AccountStatus.Active,
    val isVerified: Boolean = false,
    val settings: UserSettings = UserSettings(),
    val createdAt: PgInstant = Instant.EPOCH,
    /** Version of the terms & privacy policy the user accepted (GDPR consent record). */
    val acceptedTermsVersion: String? = null,
    val acceptedTermsAt: PgInstant? = null,
    /** When a suspension or ban ends (null = until lifted by the team). */
    val statusUntil: PgInstant? = null,
    val statusReason: String? = null,
    /** Set once the "Confirm your email" link was opened (right away for Apple/Google sign-ups). */
    val emailVerifiedAt: PgInstant? = null,
)

@Serializable
data class UserSettings(
    val pushEnabled: Boolean = true,
    val emailEnabled: Boolean = true,
    val bookingUpdates: Boolean = true,
    val messages: Boolean = true,
    val reminders: Boolean = true,
    val reviewPrompts: Boolean = true,
    val marketing: Boolean = false,
    val searchRadiusKm: Double = 10.0,
    val useMetricUnits: Boolean = true,
)

/** Public artist profile (`artist_profiles` table). `id` equals the account id. */
@Serializable
data class ArtistProfile(
    val id: String,
    val artistName: String = "",
    val genres: List<Genre> = emptyList(),
    val city: String = "",
    val bio: String = "",
    val avatarUrl: String? = null,
    val links: List<SocialLink> = emptyList(),
    val isVerified: Boolean = false,
    /** Cosmetic "EasySesh team" badge (set by admins). */
    val hasAdminBadge: Boolean? = null,
    /** Average of the ratings studios gave this artist (1–5), and how many. */
    val ratingAverage: Double? = null,
    val reviewCount: Int? = null,
    /** Promoted artists are shown first, with a Promoted tag, when studios look for artists. Set by the server only. */
    val promotedUntil: PgInstant? = null,
) {
    val isComplete: Boolean get() = artistName.isNotBlank() && city.isNotEmpty()
    val isPromoted: Boolean get() = (promotedUntil ?: Instant.MIN).isAfter(Instant.now())

    companion object {
        fun empty(id: String) = ArtistProfile(id = id)
    }
}

@Serializable
data class SocialLink(val platform: SocialPlatform, val url: String) {
    val id: String get() = platform.raw + url

    /** A tappable address, also when people typed just their username ("name", "@name") or a site without "https://". */
    val resolvedUrl: String? get() = resolve(url, platform)

    companion object {
        fun resolve(raw: String, platform: SocialPlatform): String? {
            val text = raw.trim()
            if (text.isEmpty()) return null
            val lower = text.lowercase()
            if (lower.startsWith("http://") || lower.startsWith("https://")) return text
            // Looks like a domain or path ("open.spotify.com/…", "mysite.dk")
            if (text.contains(".") && !text.startsWith("@") && !text.contains(" ")) return "https://$text"
            val handle = URLEncoder.encode(text.trim('@', '/', ' '), "UTF-8").replace("+", "%20")
            return when (platform) {
                SocialPlatform.Instagram -> "https://www.instagram.com/$handle"
                SocialPlatform.Tiktok -> "https://www.tiktok.com/@$handle"
                SocialPlatform.Youtube -> "https://www.youtube.com/@$handle"
                SocialPlatform.Soundcloud -> "https://soundcloud.com/$handle"
                SocialPlatform.Spotify -> "https://open.spotify.com/search/$handle"
                SocialPlatform.AppleMusic -> "https://music.apple.com/search?term=$handle"
                SocialPlatform.Website -> "https://$handle"
            }
        }
    }
}
