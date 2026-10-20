package com.easysesh.app.ui.features

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.model.ArtistReview
import com.easysesh.app.model.RatingKind
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.SocialPlatform
import com.easysesh.app.model.Studio
import com.easysesh.app.model.StudioArtistLink
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch

val SocialPlatform.brandColors: List<Color>
    get() = when (this) {
        SocialPlatform.Spotify -> listOf(Color(0.11f, 0.73f, 0.33f), Color(0.05f, 0.5f, 0.25f))
        SocialPlatform.AppleMusic -> listOf(Color(0.98f, 0.26f, 0.41f), Color(0.99f, 0.44f, 0.3f))
        SocialPlatform.Instagram -> listOf(Color(0.51f, 0.23f, 0.71f), Color(0.99f, 0.35f, 0.3f))
        SocialPlatform.Tiktok -> listOf(Color(0.1f, 0.1f, 0.12f), Color(0.0f, 0.83f, 0.87f))
        SocialPlatform.Youtube -> listOf(Color(1.0f, 0.2f, 0.2f), Color(0.75f, 0.05f, 0.05f))
        SocialPlatform.Soundcloud -> listOf(Color(1.0f, 0.6f, 0.1f), Color(1.0f, 0.33f, 0.0f))
        SocialPlatform.Website -> listOf(Color(0.45f, 0.4f, 1.0f), Color(0.25f, 0.8f, 1.0f))
    }

/**
 * An artist's public profile: seen by studios (from a chat, booking or studio page) and by the
 * artist themself, who can also dispute ratings and confirm studio connections here.
 */
@Composable
fun ArtistPublicProfileView(artistId: String, initial: ArtistProfile?) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var profile by remember { mutableStateOf<ArtistProfile?>(null) }
    var reviews by remember { mutableStateOf<List<ArtistReview>>(emptyList()) }
    var links by remember { mutableStateOf<List<StudioArtistLink>>(emptyList()) }
    var studios by remember { mutableStateOf<Map<String, Studio>>(emptyMap()) }
    var disputing by remember { mutableStateOf<ArtistReview?>(null) }
    var disputed by remember { mutableStateOf(setOf<String>()) }
    var error by remember { mutableStateOf<String?>(null) }
    var showReport by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }
    val isOwn = app.account?.id == artistId
    val shown = profile ?: initial

    LaunchedEffect(reload) {
        if (!isOwn && app.account != null) runCatching { app.backend.blockedUsers() }.getOrNull()?.let { list -> blocked = list.any { it.userId == artistId } }
        try {
            profile = app.backend.artistProfile(artistId) ?: profile
            reviews = app.backend.artistReviews(artistId)
            links = app.backend.artistStudioLinks(artistId)
            val loaded = studios.toMutableMap()
            links.forEach { link -> if (loaded[link.studioId] == null) runCatching { app.backend.studio(link.studioId) }.getOrNull()?.let { loaded[link.studioId] = it } }
            studios = loaded
        } catch (e: Exception) { error = e.userMessage }
    }

    fun setBlocked(block: Boolean) {
        app.scope.launch {
            try {
                if (block) app.backend.blockUser(artistId) else app.backend.unblockUser(artistId)
                blocked = block
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    fun respond(link: StudioArtistLink, accept: Boolean) {
        app.scope.launch {
            try { app.backend.respondStudioArtistLink(link.studioId, accept); reload++ } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen(shown?.artistName ?: tr("Artist"), translateTitle = false, auroraHeight = 420.dp, actions = {
        if (!isOwn && app.account != null) {
            Box {
                GlassIcon("ellipsis.circle", Modifier.pressable { menu = true })
                DropdownMenu(menu, { menu = false }, containerColor = Theme.card) {
                    MenuItem("Report artist", "flag") { menu = false; showReport = true }
                    if (blocked) MenuItem("Unblock", "hand.raised.slash") { menu = false; setBlocked(false) }
                    else MenuItem("Block artist", "hand.raised.fill", destructive = true) { menu = false; confirmBlock = true }
                }
            }
        }
    }) {
        shown?.let { p ->
            // Hero
            GlassCard(padding = 20.dp, cornerRadius = 26.dp) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(contentAlignment = Alignment.Center) {
                        Box(Modifier.size(124.dp).blur(18.dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded).graphicsLayer { alpha = 0.5f }.background(Theme.neon, CircleShape))
                        Avatar(p.avatarUrl, p.artistName, 104.dp, Modifier.padding(4.dp))
                        Box(Modifier.size(112.dp).border(3.dp, Theme.neon, CircleShape))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(p.artistName, style = Type.system(26, FontWeight.ExtraBold).tracking(-0.5f))
                        if (p.isVerified) VerifiedBadge()
                        if (p.hasAdminBadge == true) AdminBadge()
                        if (p.isPromoted) PromotedTag()
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (p.city.isNotEmpty()) {
                            Row(Modifier.background(Theme.card.copy(alpha = 0.78f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Sym("mappin.and.ellipse", size = 14.dp, tint = Theme.secondary)
                                Txt(p.city, style = Type.subheadline.semibold, color = Theme.secondary)
                            }
                        }
                        RatingPill(p.ratingAverage ?: 0.0, p.reviewCount ?: 0)
                    }
                    if (p.genres.isNotEmpty()) {
                        FlowLayout(6.dp) {
                            p.genres.forEach { genre ->
                                T(genre.title, Modifier.background(Theme.violet.copy(alpha = 0.14f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp), style = Type.caption.bold, color = Theme.violet)
                            }
                        }
                    }
                    if (p.bio.isNotEmpty()) Txt(p.bio, style = Type.subheadline, color = Theme.secondary, align = TextAlign.Center)
                }
            }
            if (p.links.isNotEmpty()) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    p.links.forEach { link ->
                        val url = link.resolvedUrl ?: return@forEach
                        Row(
                            Modifier.background(Theme.card.copy(alpha = 0.78f), CircleShape).border(0.8.dp, Theme.colors.glassEdge, CircleShape)
                                .pressable { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
                                .padding(start = 6.dp, end = 14.dp, top = 6.dp, bottom = 6.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconTile(link.platform.symbol, 26.dp, link.platform.brandColors)
                            T(link.platform.title, style = Type.subheadline.semibold)
                        }
                    }
                }
            }
        }
        // Studio connections
        val accepted = links.filter { it.isAccepted }
        val pending = links.filter { !it.isAccepted }
        if (isOwn) {
            pending.forEach { link ->
                GlassCard {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            IconTile("link", 36.dp, TilePalette.violet)
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                T("Connect your studio?", style = Type.subheadline.bold)
                                Txt(L10n.format("%@ wants to show your artist profile on its page, and the studio on your profile.", studios[link.studioId]?.name ?: tr("A studio")),
                                    style = Type.caption, color = Theme.secondary)
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            SecondaryButton("Decline", Modifier.weight(1f)) { respond(link, false) }
                            PrimaryButton("Connect", Modifier.weight(1f)) { respond(link, true) }
                        }
                    }
                }
            }
        }
        if (accepted.isNotEmpty()) {
            GlowSectionHeader("Studio")
            accepted.forEach { link ->
                val studio = studios[link.studioId] ?: return@forEach
                NavLink({ StudioDetailView(studio.id, studio) }) {
                    GlassCard(padding = 12.dp) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            RemoteImage(studio.photoUrls.firstOrNull(), Modifier.size(54.dp).clip(RoundedCornerShape(14.dp)))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Txt(studio.name, style = Type.headline)
                                Txt(studio.address.publicArea, style = Type.caption, color = Theme.secondary)
                            }
                            if (isOwn) {
                                Box(Modifier.pressable { app.scope.launch { runCatching { app.backend.removeStudioArtistLink(studio.id, artistId) }; reload++ } }) {
                                    Sym("link.badge.plus", Modifier.graphicsLayer { rotationZ = 45f }, tint = Theme.secondary)
                                }
                            }
                            Sym("chevron.right", size = 14.dp, tint = Theme.tertiary)
                        }
                    }
                }
            }
        }
        // Ratings
        GlowSectionHeader("Ratings from studios", reviews.size)
        if (reviews.isEmpty()) GlassEmptyState("No ratings yet", "star.bubble.fill", "Studios can rate artists after a completed session.")
        reviews.forEach { review ->
            GlassCard(padding = 14.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(review.studioName, Modifier.weight(1f), style = Type.subheadline.bold)
                        StarsView(review.rating, 13.dp)
                    }
                    if (review.text.isNotEmpty()) Txt(review.text, style = Type.subheadline, color = Theme.secondary)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(Dates.abbreviated(review.createdAt), Modifier.weight(1f), style = Type.caption2, color = Theme.tertiary)
                        if (isOwn) {
                            if (review.id in disputed) {
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Sym("checkmark.circle.fill", size = 13.dp, tint = Theme.positive)
                                    T("Dispute sent", style = Type.caption.semibold, color = Theme.positive)
                                }
                            } else {
                                Row(Modifier.pressable { disputing = review }, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Sym("flag.fill", size = 13.dp, tint = Theme.accent)
                                    T("Dispute", style = Type.caption.semibold, color = Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (confirmBlock) {
        ConfirmDialog(L10n.format("Block %@?", shown?.artistName ?: tr("Artist")), tr("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts."),
            listOf(DialogAction("Block", destructive = true) { setBlocked(true) }), { confirmBlock = false }, translateTitle = false)
    }
    if (showReport) Sheet({ showReport = false }) { ReportSheet(ReportTarget.User, artistId) }
    disputing?.let { review -> Sheet({ disputing = null }) { DisputeRatingSheet(RatingKind.ArtistReview, review.id) { disputed = disputed + review.id } } }
    ErrorAlert(error) { error = null }
}

/** Ask EasySesh to look at a rating you think is unfair. */
@Composable
fun DisputeRatingSheet(kind: RatingKind, reviewId: String, onSent: () -> Unit = {}) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var reason by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    NavScreen("", leading = { ToolbarButton("Cancel") { dismiss() } }, auroraHeight = 300.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            IconTile("scale.3d", 44.dp, TilePalette.violet)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                T("Dispute this rating", style = Type.title3.heavy)
                T("Our team checks the booking and the rating. If it breaks our guidelines or isn't about a real session, we remove it.", style = Type.subheadline, color = Theme.secondary)
            }
        }
        Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.78f), RoundedCornerShape(18.dp)).border(1.dp, Theme.primary.copy(alpha = 0.1f), RoundedCornerShape(18.dp)).padding(14.dp)) {
            PlainTextField(reason, { reason = it }, "Why is this rating unfair?", Modifier.fillMaxWidth(), minLines = 5, maxLines = 10)
        }
        PrimaryButton(if (isSending) "Sending…" else "Send dispute", enabled = !isSending && reason.trim().length >= 10) {
            isSending = true
            app.scope.launch {
                try {
                    app.backend.disputeRating(kind, reviewId, reason)
                    onSent()
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isSending = false }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun StarsView(rating: Int, size: androidx.compose.ui.unit.Dp = 14.dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (star in 1..5) Sym(if (star <= rating) "star.fill" else "star", size = size + 2.dp, tint = if (star <= rating) Theme.magenta else Theme.secondary.copy(alpha = 0.4f))
    }
}
