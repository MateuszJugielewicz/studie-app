package com.easysesh.app.model

import com.easysesh.app.core.PgInstant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/** Chat is always scoped to one artist + one studio, optionally tied to a booking. */
@Serializable
data class Conversation(
    val id: String,
    val artistId: String,
    val studioId: String,
    val bookingId: String? = null,
    val artistName: String = "",
    val studioName: String = "",
    val studioPhotoUrl: String? = null,
    val lastMessagePreview: String = "",
    val lastMessageAt: PgInstant = Instant.EPOCH,
    val artistUnread: Int = 0,
    val studioUnread: Int = 0,
    /** null on databases that predate message requests (treated as accepted). */
    val requestStatus: ConversationRequestStatus? = null,
    val startedByStudio: Boolean? = null,
    val artistAvatarUrl: String? = null,
) {
    fun unread(role: UserRole) = if (role == UserRole.Artist) artistUnread else studioUnread
    val status get() = requestStatus ?: ConversationRequestStatus.Accepted
    /** A studio wrote first and the artist hasn't accepted yet. */
    val isPendingRequest get() = status == ConversationRequestStatus.Pending
    val isDeclined get() = status == ConversationRequestStatus.Declined

    /** Unread messages that count towards the tab badge. Requests and declined threads don't. */
    fun badgeCount(role: UserRole): Int {
        if (role == UserRole.Artist && status != ConversationRequestStatus.Accepted) return 0
        return unread(role)
    }

    fun title(role: UserRole) = if (role == UserRole.Artist) studioName else artistName
}

@Serializable
enum class ConversationRequestStatus { @SerialName("accepted") Accepted, @SerialName("pending") Pending, @SerialName("declined") Declined }

/** Artist found by a studio when starting a new conversation. */
@Serializable
data class ArtistSearchResult(
    val id: String,
    val artistName: String,
    val city: String = "",
    val genres: List<String> = emptyList(),
    val avatarUrl: String? = null,
    val isVerified: Boolean = false,
    /** Has booked this studio before (skips the message request). */
    val hasBooked: Boolean = false,
    val hasAdminBadge: Boolean? = null,
    /** Bought (or was given) a promotion: listed first, with a Promoted tag. */
    val isPromoted: Boolean? = null,
)

/** Someone with live stories, for the row of circles (`story_feed`). */
@Serializable
data class StoryAuthor(
    val userId: String,
    val studioId: String? = null,
    val name: String,
    val avatarUrl: String? = null,
    val isVerified: Boolean = false,
    val isPromoted: Boolean = false,
    val storyCount: Int = 0,
    val latestAt: PgInstant? = null,
    val allSeen: Boolean = false,
    val isOwn: Boolean = false,
)

/** One 24-hour story (`user_stories`). Views and replies are only filled in for the poster. */
@Serializable
data class Story(
    val id: String,
    val userId: String,
    val studioId: String? = null,
    val mediaUrl: String,
    val caption: String = "",
    val createdAt: PgInstant,
    val expiresAt: PgInstant,
    val likeCount: Int = 0,
    val likedByMe: Boolean = false,
    val viewCount: Int? = null,
    val replyCount: Int? = null,
    val seen: Boolean = false,
)

/** Who viewed, liked or replied to the poster's story (`story_activity`). */
@Serializable
data class StoryActivity(
    val personId: String,
    val name: String,
    val avatarUrl: String? = null,
    val viewedAt: PgInstant? = null,
    val liked: Boolean = false,
    val reply: String? = null,
    val repliedAt: PgInstant? = null,
)

/** An application for the verified badge (artist profile or studio), reviewed by the EasySesh team. */
@Serializable
data class VerificationRequest(
    val id: String,
    val userId: String,
    val studioId: String? = null,
    val kind: String,
    val status: String,
    val message: String = "",
    val links: List<String> = emptyList(),
    val staffNote: String? = null,
    val reviewedAt: PgInstant? = null,
    val createdAt: PgInstant,
)

/** An artist in the studios' "Find artists" list (`discover_artists`). */
@Serializable
data class DiscoveredArtist(
    val id: String,
    val artistName: String,
    val city: String = "",
    val genres: List<String> = emptyList(),
    val avatarUrl: String? = null,
    val bio: String = "",
    val isVerified: Boolean = false,
    val hasAdminBadge: Boolean = false,
    val ratingAverage: Double = 0.0,
    val reviewCount: Int = 0,
    val sessionCount: Int = 0,
    val isPromoted: Boolean = false,
    /** Has booked this studio before (messages skip the request step). */
    val hasBooked: Boolean = false,
    val joinedAt: PgInstant? = null,
) {
    val searchResult get() = ArtistSearchResult(id, artistName, city, genres, avatarUrl, isVerified, hasBooked, hasAdminBadge, isPromoted)
}

@Serializable
data class ChatMessage(
    val id: String,
    val conversationId: String,
    /** null for system messages. */
    val senderId: String? = null,
    val kind: MessageKind = MessageKind.Text,
    val body: String,
    val createdAt: PgInstant,
)

@Serializable
data class Review(
    val id: String,
    val bookingId: String,
    val studioId: String,
    val artistId: String,
    val artistName: String,
    val rating: Int,
    val facilitiesRating: Int,
    val experienceRating: Int,
    /** null when the session had no engineer/producer. */
    val engineerRating: Int? = null,
    val text: String = "",
    val studioReply: String? = null,
    val studioRepliedAt: PgInstant? = null,
    val isHidden: Boolean = false,
    val createdAt: PgInstant,
)

@Serializable
data class AppNotification(
    val id: String,
    val userId: String,
    val kind: NotificationKind = NotificationKind.System,
    val title: String,
    val body: String = "",
    val isRead: Boolean = false,
    val bookingId: String? = null,
    val conversationId: String? = null,
    val studioId: String? = null,
    val createdAt: PgInstant,
)

@Serializable
data class Report(
    val id: String,
    val reporterId: String,
    val targetType: ReportTarget,
    val targetId: String,
    val reason: ReportReason,
    val details: String,
    val status: ReportStatus,
    val createdAt: PgInstant,
)

// MARK: Support

@Serializable
enum class SupportCategory(val title: String, val symbol: String) {
    @SerialName("account") Account("Account & login", "person.crop.circle"),
    @SerialName("booking") Booking("A booking", "calendar"),
    @SerialName("payment") Payment("Payments & refunds", "creditcard"),
    @SerialName("studio") Studio("My studio listing", "music.mic"),
    @SerialName("bug") Bug("Something isn't working", "ladybug"),
    @SerialName("other") Other("Something else", "questionmark.bubble"),
}

@Serializable
enum class SupportTicketStatus(val title: String) {
    /** Waiting for EasySesh. */
    @SerialName("open") Open("Waiting for EasySesh"),
    /** EasySesh replied; waiting for the user. */
    @SerialName("answered") Answered("EasySesh replied"),
    @SerialName("closed") Closed("Closed"),
}

@Serializable
data class SupportTicket(
    val id: String,
    val userId: String,
    val subject: String,
    val category: SupportCategory,
    val bookingId: String? = null,
    val status: SupportTicketStatus,
    val userUnread: Int = 0,
    val lastMessagePreview: String = "",
    val lastMessageAt: PgInstant,
    val createdAt: PgInstant,
    /** 1–5 stars the user gave after the request was closed. */
    val rating: Int? = null,
    val ratingComment: String? = null,
)

@Serializable
data class SupportMessage(
    val id: String,
    val ticketId: String,
    val senderId: String? = null,
    val fromAdmin: Boolean = false,
    val body: String,
    val createdAt: PgInstant,
)

/** Artist ratings (given by studios). */
@Serializable
data class ArtistReview(
    val id: String,
    val bookingId: String,
    val studioId: String,
    val artistId: String,
    val studioName: String,
    val rating: Int,
    val text: String = "",
    val createdAt: PgInstant,
)

// MARK: Promotions

@Serializable
enum class PromotionPackage(val raw: String, val days: Int, val title: String) {
    @SerialName("week") Week("week", 7, "1 week"),
    @SerialName("two_weeks") TwoWeeks("two_weeks", 14, "2 weeks"),
    @SerialName("month") Month("month", 30, "1 month"),
    @SerialName("custom") Custom("custom", 0, "Promotion");

    /** Same table as `promotion_price` in the database (which decides what is charged). */
    fun price(currency: String): Int {
        val table = mapOf(
            "DKK" to listOf(14900, 26900, 44900), "SEK" to listOf(21900, 39900, 65900), "NOK" to listOf(21900, 39900, 65900),
            "GBP" to listOf(1600, 2900, 4900), "USD" to listOf(2100, 3900, 6500), "PLN" to listOf(8900, 15900, 25900),
        )
        val prices = table[currency.uppercase()] ?: listOf(1900, 3500, 5900)
        return when (this) {
            Week -> prices[0]
            TwoWeeks -> prices[1]
            Month -> prices[2]
            Custom -> 0
        }
    }

    companion object { val purchasable = listOf(Week, TwoWeeks, Month) }
}

@Serializable
enum class PromotionStatus { @SerialName("pending") Pending, @SerialName("active") Active, @SerialName("expired") Expired, @SerialName("cancelled") Cancelled }

@Serializable
data class StudioPromotion(
    val id: String,
    val studioId: String,
    @SerialName("package") val promotionPackage: PromotionPackage = PromotionPackage.Custom,
    val days: Int = 0,
    val amount: Int = 0,
    val currency: String = "EUR",
    val status: PromotionStatus,
    val source: String = "",
    val startsAt: PgInstant? = null,
    val endsAt: PgInstant? = null,
    val createdAt: PgInstant,
)

/** Studio ↔ artist profile connection. */
@Serializable
data class StudioArtistLink(val studioId: String, val artistId: String, val status: String, val createdAt: PgInstant) {
    val isAccepted get() = status == "accepted"
}

@Serializable
enum class RatingKind(val raw: String) {
    /** An artist's review of a studio (disputed by the studio). */
    @SerialName("studio_review") StudioReview("studio_review"),
    /** A studio's rating of an artist (disputed by the artist). */
    @SerialName("artist_review") ArtistReview("artist_review"),
}

/** A warning from the EasySesh team, shown until the user acknowledges it. */
@Serializable
data class ModerationWarning(val id: String, val reason: String, val createdAt: PgInstant, val acknowledgedAt: PgInstant? = null)

/** A warning, suspension, ban or lifted restriction on the account (`moderation_actions`). */
@Serializable
data class ModerationRecord(
    val id: String,
    /** warning | suspension | ban | lifted */
    val action: String,
    val reason: String = "",
    val endsAt: PgInstant? = null,
    val createdAt: PgInstant,
    val studioId: String? = null,
) {
    val title: String get() = when (action) {
        "warning" -> "Warning"
        "ban" -> "Account banned"
        "lifted" -> "Restriction lifted"
        else -> if (studioId != null) "Studio suspended" else "Account suspended"
    }
}

/** "Changes to your account" made by the EasySesh team (also emailed). */
@Serializable
data class AccountChangeNotice(val id: String, val changes: List<String> = emptyList(), val reason: String? = null, val createdAt: PgInstant)

/** An update note written by the EasySesh team ("What's new"). */
@Serializable
data class ChangelogEntry(
    val id: String,
    val version: String,
    val title: String,
    val body: String = "",
    val audience: String = "all",
    val isLegalUpdate: Boolean = false,
    val publishedAt: PgInstant,
) {
    fun isFor(role: UserRole) = audience == "all" || audience == role.raw
}

@Serializable
data class FeeInvoice(
    val id: String,
    val studioId: String,
    val amount: Int,
    val currency: String,
    val status: String,
    val hostedInvoiceUrl: String? = null,
    val dueAt: PgInstant? = null,
    val createdAt: PgInstant,
) {
    val isOverdue get() = status == "open" && (dueAt ?: Instant.MAX).isBefore(Instant.now())
    val isInCollections get() = status == "collections"
    val statusTitle
        get() = when (status) {
            "paid" -> "Paid"
            "collections" -> "Debt collection"
            "void" -> "Cancelled"
            else -> if (isOverdue) "Overdue" else "Open"
        }
}

/** Whether either side of a conversation blocked the other. */
@Serializable
enum class BlockState(val raw: String) {
    @SerialName("none") None("none"),
    @SerialName("by_me") ByMe("by_me"),
    @SerialName("by_them") ByThem("by_them");

    companion object { fun from(raw: String) = entries.firstOrNull { it.raw == raw } ?: None }
}

@Serializable
data class BlockedUser(val userId: String, val displayName: String, val avatarUrl: String? = null, val blockedAt: PgInstant) {
    val id get() = userId
}
