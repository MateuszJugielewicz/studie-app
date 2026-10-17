package com.easysesh.app.ui.features

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.model.ArtistSearchResult
import com.easysesh.app.model.PromotionStatus
import com.easysesh.app.model.Studio
import com.easysesh.app.model.StudioArtistLink
import com.easysesh.app.model.StudioPromotion
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val PromotionStatus.title: String
    get() = when (this) {
        PromotionStatus.Pending -> "Waiting for payment"
        PromotionStatus.Active -> "Active"
        PromotionStatus.Expired -> "Ended"
        PromotionStatus.Cancelled -> "Cancelled"
    }

/**
 * A studio's promotion status: a "Promoted" tag and a place at the top of search for a period.
 * Promotions are granted by the EasySesh team (admin panel); the app doesn't sell them.
 */
@Composable
fun PromotionView(studio: Studio) {
    val app = LocalAppState.current
    var promotions by remember { mutableStateOf<List<StudioPromotion>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    val active = promotions.firstOrNull { it.status == PromotionStatus.Active }
    val history = promotions.filter { it.status != PromotionStatus.Pending && it.status != PromotionStatus.Active }

    LaunchedEffect(Unit) {
        try { promotions = app.backend.promotions(studio.id) } catch (e: Exception) { error = e.userMessage }
    }

    NavScreen("Promote", auroraHeight = 380.dp) {
        GlassCard(Modifier.padding(top = 8.dp), padding = 18.dp, cornerRadius = 24.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                IconTile("megaphone.fill", 48.dp, TilePalette.signal)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    T("Get seen first", style = Type.system(26, FontWeight.ExtraBold).tracking(-0.5f))
                    T("Promoted studios are shown at the top of Discover and search, with a Promoted tag.", style = Type.subheadline, color = Theme.secondary)
                }
            }
            VSpace(12.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                PromotedTag()
                Sym("arrow.right", size = 12.dp, tint = Theme.secondary)
                Sym("arrow.up.to.line", size = 12.dp, tint = Theme.secondary)
                T("Top of results", style = Type.caption.semibold, color = Theme.secondary)
            }
        }

        if (active != null) {
            GlassCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    PulseDot(Theme.positive, true)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        T("Your studio is promoted", style = Type.headline)
                        (active.endsAt ?: studio.promotedUntil)?.let { end ->
                            Txt(L10n.format("Until %@", Dates.abbreviatedWithTime(end)), style = Type.subheadline, color = Theme.secondary)
                        }
                    }
                    PromotedTag()
                }
            }
        } else {
            // Store rules: promotions shown in this app can't be sold here, so the app only shows status.
            GlassCard(padding = 16.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Sym("info.circle", size = 16.dp, tint = Theme.secondary)
                    T("Your studio isn't promoted right now.", style = Type.subheadline, color = Theme.secondary)
                }
            }
        }

        if (history.isNotEmpty()) {
            GlowSectionHeader("History", history.size)
            history.forEach { promotion ->
                GlassCard(padding = 12.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T(promotion.promotionPackage.title, style = Type.subheadline.semibold)
                            Txt(Dates.abbreviated(promotion.createdAt), style = Type.caption, color = Theme.secondary)
                        }
                        Txt(Money.format(promotion.amount, promotion.currency), style = Type.subheadline)
                        StatusPill(tr(promotion.status.title), if (promotion.status == PromotionStatus.Expired) Theme.secondary else Theme.red)
                    }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

/**
 * A studio shows its owner's artist profile on its page (and the studio appears on the artist
 * profile) once the artist confirms.
 */
@Composable
fun StudioArtistLinkView(studio: Studio) {
    val app = LocalAppState.current
    val navigator = LocalNavigator.current
    var link by remember { mutableStateOf<StudioArtistLink?>(null) }
    var linkedArtist by remember { mutableStateOf<ArtistProfile?>(null) }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<ArtistSearchResult>>(emptyList()) }
    var isWorking by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try {
            link = app.backend.studioArtistLink(studio.id)
            link?.let { l -> linkedArtist = runCatching { app.backend.artistProfile(l.artistId) }.getOrNull() }
        } catch (e: Exception) { error = e.userMessage }
    }
    LaunchedEffect(query) {
        if (query.length < 2) { results = emptyList(); return@LaunchedEffect }
        delay(250)
        results = runCatching { app.backend.searchArtists(query) }.getOrDefault(emptyList())
    }

    fun request(artist: ArtistSearchResult) {
        isWorking = true
        app.scope.launch {
            try {
                link = app.backend.requestStudioArtistLink(artist.id)
                linkedArtist = runCatching { app.backend.artistProfile(artist.id) }.getOrNull()
            } catch (e: Exception) { error = e.userMessage }
            isWorking = false
        }
    }

    fun remove() {
        isWorking = true
        app.scope.launch {
            try {
                app.backend.removeStudioArtistLink(studio.id)
                link = null
                linkedArtist = null
            } catch (e: Exception) { error = e.userMessage }
            isWorking = false
        }
    }

    NavScreen("Artist profile") {
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            IconTile("link", 48.dp, TilePalette.violet)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                T("Your artist profile", style = Type.system(26, FontWeight.ExtraBold).tracking(-0.5f))
                T("Are you an artist too? Connect your artist profile: it's shown on your studio page, and your studio on your artist profile.", style = Type.subheadline, color = Theme.secondary)
            }
        }

        val current = link
        if (current != null) {
            GlassCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(linkedArtist?.avatarUrl, linkedArtist?.artistName ?: "?", 48.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Txt(linkedArtist?.artistName ?: "…", style = Type.headline)
                            T(if (current.isAccepted) "Connected" else "Waiting for the artist to confirm in their profile", style = Type.caption,
                                color = if (current.isAccepted) Theme.positive else Theme.secondary)
                        }
                    }
                    if (current.isAccepted) {
                        Row(Modifier.pressable { navigator?.push { ArtistPublicProfileView(current.artistId, linkedArtist) } },
                            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Sym("person.crop.circle", size = 16.dp, tint = Theme.accent)
                            T("View artist profile", style = Type.subheadline.semibold, color = Theme.accent)
                        }
                    }
                    SecondaryButton(if (current.isAccepted) "Remove connection" else "Cancel request", Modifier.fillMaxWidth(), enabled = !isWorking, color = Theme.red) { remove() }
                }
            }
        } else {
            GlassField("magnifyingglass", focused) {
                PlainTextField(query, { query = it }, "Search your artist name", Modifier.weight(1f).onFocusChanged { focused = it.isFocused },
                    capitalization = KeyboardCapitalization.None)
            }
            T("The artist has to confirm the connection from their profile, so only your own profile can be connected.", style = Type.caption, color = Theme.secondary)
            results.forEach { artist ->
                GlassCard(padding = 12.dp) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(artist.avatarUrl, artist.artistName, 42.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(artist.artistName, style = Type.subheadline.semibold)
                                if (artist.isVerified) VerifiedBadge()
                                if (artist.hasAdminBadge == true) AdminBadge(compact = true)
                            }
                            if (artist.city.isNotEmpty()) Txt(artist.city, style = Type.caption, color = Theme.secondary)
                        }
                        PrimaryButton("Connect", enabled = !isWorking) { request(artist) }
                    }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
