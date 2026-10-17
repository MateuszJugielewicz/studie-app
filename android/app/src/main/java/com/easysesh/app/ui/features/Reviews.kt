package com.easysesh.app.ui.features

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.AuthRoute
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.Booking
import com.easysesh.app.model.RatingKind
import com.easysesh.app.model.ReportReason
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.Review
import com.easysesh.app.model.Studio
import com.easysesh.app.model.UserRole
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

@Composable
fun ReviewSummaryView(studio: Studio, reviews: List<Review>) {
    fun average(value: (Review) -> Int) = if (reviews.isEmpty()) 0.0 else reviews.sumOf(value).toDouble() / reviews.size
    GlassCard(cornerRadius = Theme.corner) {
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Txt(if (studio.reviewCount == 0) "–" else String.format(Locale.getDefault(), "%.1f", studio.ratingAverage), style = Type.display(44))
                StarRow(studio.ratingAverage.roundToInt())
                Txt(L10n.format("%lld reviews", studio.reviewCount), style = Type.caption, color = Theme.secondary)
            }
            if (reviews.isNotEmpty()) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Bar("Facilities", average { it.facilitiesRating })
                    Bar("Experience", average { it.experienceRating })
                    val engineer = reviews.mapNotNull { it.engineerRating }
                    if (engineer.isNotEmpty()) Bar("Engineer", engineer.sum().toDouble() / engineer.size)
                }
            }
        }
    }
}

@Composable
private fun Bar(title: String, value: Double) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        T(title, Modifier.width(72.dp), style = Type.caption)
        LinearProgressIndicator({ (value / 5).toFloat() }, Modifier.weight(1f), color = Theme.primary, trackColor = Theme.fill, drawStopIndicator = {})
        Txt(String.format(Locale.getDefault(), "%.1f", value), style = Type.caption)
    }
}

@Composable
fun ReviewRow(initial: Review, canReply: Boolean) {
    val app = LocalAppState.current
    var review by remember { mutableStateOf(initial) }
    var showReply by remember { mutableStateOf(false) }
    var showReport by remember { mutableStateOf(false) }
    var showDispute by remember { mutableStateOf(false) }
    var disputed by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    GlassCard(cornerRadius = Theme.corner) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Avatar(null, review.artistName, 32.dp)
                Column(Modifier.weight(1f)) {
                    Txt(review.artistName, style = Type.subheadline.bold)
                    Txt(Dates.abbreviated(review.createdAt), style = Type.caption, color = Theme.secondary)
                }
                StarRow(review.rating)
                Box {
                    Box(Modifier.pressable { menu = true }.padding(6.dp)) { Sym("ellipsis", tint = Theme.secondary) }
                    DropdownMenu(menu, { menu = false }, containerColor = Theme.card) {
                        if (canReply && review.studioReply == null) MenuItem("Reply", "arrowshape.turn.up.left") { menu = false; showReply = true }
                        if (canReply && !disputed) MenuItem("Dispute rating", "scale.3d") { menu = false; showDispute = true }
                        MenuItem("Report review", "flag") {
                            menu = false
                            if (app.account == null) app.guestAuthRequest = AuthRoute(AuthRoute.Mode.SignIn, UserRole.Artist) else showReport = true
                        }
                    }
                }
            }
            if (review.text.isNotEmpty()) Txt(review.text, style = Type.subheadline)
            review.studioReply?.let { reply ->
                Column(Modifier.fillMaxWidth().background(Theme.accent.copy(alpha = 0.12f), RoundedCornerShape(10.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    T("Response from the studio", style = Type.caption.bold)
                    Txt(reply, style = Type.caption)
                }
            }
        }
    }
    if (showReport) Sheet({ showReport = false }) { ReportSheet(ReportTarget.Review, review.id) }
    if (showReply) Sheet({ showReply = false }) { ReplySheet(review) { review = it } }
    if (showDispute) Sheet({ showDispute = false }) { DisputeRatingSheet(RatingKind.StudioReview, review.id) { disputed = true } }
}

@Composable
fun MenuItem(title: String, symbol: String, destructive: Boolean = false, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { T(title, style = Type.body, color = if (destructive) Theme.red else Theme.primary) },
        leadingIcon = { Sym(symbol, tint = if (destructive) Theme.red else Theme.primary) },
        onClick = onClick,
    )
}

@Composable
fun ReplySheet(review: Review, onSaved: (Review) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    NavScreen("Reply to review", leading = { ToolbarButton("Cancel") { dismiss() } }, actions = {
        ToolbarButton("Post", enabled = text.isNotBlank(), bold = true) {
            app.scope.launch {
                try { onSaved(app.backend.replyToReview(review.id, text)); dismiss() } catch (e: Exception) { error = e.userMessage }
            }
        }
    }) {
        FormSection { FormContent { Txt(review.text, style = Type.body, color = Theme.secondary) } }
        FormSection("Your public reply") { FormTextField("Thank the artist or respond to feedback", text, { text = it }, minLines = 4, maxLines = 10) }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun ReviewsListView(studio: Studio, reviews: List<Review>, canReply: Boolean) {
    NavScreen("Reviews") {
        ReviewSummaryView(studio, reviews)
        reviews.forEach { ReviewRow(it, canReply) }
    }
}

@Composable
fun WriteReviewView(booking: Booking, onSubmitted: () -> Unit = {}) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var rating by remember { mutableStateOf(5) }
    var facilities by remember { mutableStateOf(5) }
    var experience by remember { mutableStateOf(5) }
    var hadEngineer by remember { mutableStateOf(booking.sessionTypeName.contains("engineer", ignoreCase = true) || booking.addOns.any { it.id == "producer" }) }
    var engineer by remember { mutableStateOf(5) }
    var text by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        isSaving = true
        val review = Review(
            id = UUID.randomUUID().toString(), bookingId = booking.id, studioId = booking.studioId, artistId = booking.artistId,
            artistName = app.artistProfile?.artistName ?: booking.artistName, rating = rating, facilitiesRating = facilities,
            experienceRating = experience, engineerRating = if (hadEngineer) engineer else null, text = text.trim(), createdAt = Instant.now(),
        )
        app.scope.launch {
            try {
                app.backend.submitReview(review)
                onSubmitted()
                dismiss()
            } catch (e: Exception) { error = e.userMessage } finally { isSaving = false }
        }
    }

    NavScreen("Review your session", leading = { ToolbarButton("Later") { dismiss() } }, actions = {
        ToolbarButton("Submit", enabled = !isSaving && text.length >= 10, bold = true) { submit() }
    }) {
        FormSection {
            FormContent {
                Txt(booking.studioName, style = Type.headline)
                Txt("${booking.sessionTypeName} · ${Dates.abbreviated(booking.startsAt)}", style = Type.caption, color = Theme.secondary)
            }
        }
        FormSection("Ratings") {
            FormContent { StarPicker("Overall", rating) { rating = it } }
            FormContent { StarPicker("Facilities", facilities) { facilities = it } }
            FormContent { StarPicker("Studio experience", experience) { experience = it } }
            FormToggle("I worked with an engineer/producer", hadEngineer) { hadEngineer = it }
            if (hadEngineer) FormContent { StarPicker("Engineer/producer", engineer) { engineer = it } }
        }
        FormSection("Your review", footer = "Reviews are public and shown with your artist name.") {
            FormTextField("What was great? What could be better?", text, { text = it }, minLines = 4, maxLines = 12)
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun ReportSheet(target: ReportTarget, targetId: String) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var reason by remember { mutableStateOf<ReportReason?>(null) }
    var details by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    NavScreen("", leading = { ToolbarButton(if (sent) "Done" else "Cancel") { dismiss() } }, auroraHeight = 320.dp) {
        if (sent) {
            Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(Modifier.padding(top = 40.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(110.dp).blur(20.dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded).background(Theme.neon, CircleShape))
                    IconTile("checkmark.shield.fill", 84.dp, TilePalette.mint)
                }
                T("Thanks for letting us know", style = Type.title2.heavy, align = TextAlign.Center)
                T("Our moderation team will look into it, usually within 24 hours. We may contact you if we need more details.",
                    style = Type.subheadline, color = Theme.secondary, align = TextAlign.Center)
                PrimaryButton("Done", Modifier.padding(top = 8.dp)) { dismiss() }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                IconTile("flag.fill", 48.dp, TilePalette.signal)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    T(target.reportTitle, style = Type.system(26, androidx.compose.ui.text.font.FontWeight.ExtraBold).tracking(-0.5f))
                    T("Reports are private. The other side isn't told who reported them.", style = Type.subheadline, color = Theme.secondary)
                }
            }
            GlowSectionHeader("What's wrong?")
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ReportReason.entries.forEach { option ->
                    val selected = reason == option
                    val shape = RoundedCornerShape(18.dp)
                    Row(
                        Modifier.fillMaxWidth().background(Theme.card.copy(alpha = if (selected) 0.95f else 0.7f), shape)
                            .border(if (selected) 1.5.dp else 0.8.dp, if (selected) Theme.neon else Theme.colors.glassEdge, shape)
                            .pressable { reason = option }.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(option.symbol, 34.dp, if (selected) TilePalette.signal else TilePalette.muted)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T(option.title, style = Type.subheadline.semibold)
                            T(option.hint, style = Type.caption, color = Theme.secondary)
                        }
                        Sym(if (selected) "checkmark.circle.fill" else "circle", size = 22.dp, tint = if (selected) Theme.accent else Theme.secondary.copy(alpha = 0.5f))
                    }
                }
            }
            GlowSectionHeader("Details (optional)")
            Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.78f), RoundedCornerShape(18.dp)).border(1.dp, Theme.primary.copy(alpha = 0.1f), RoundedCornerShape(18.dp)).padding(14.dp)) {
                PlainTextField(details, { details = it }, "Tell us what happened. Dates, messages and names help us act faster.", Modifier.fillMaxWidth(), minLines = 3, maxLines = 8)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Sym("exclamationmark.shield.fill", size = 14.dp, tint = Theme.secondary)
                T("If someone is in danger, contact the local emergency services first.", style = Type.caption, color = Theme.secondary)
            }
            PrimaryButton(if (isSending) "Sending…" else "Send report", enabled = reason != null && !isSending) {
                val chosen = reason ?: return@PrimaryButton
                isSending = true
                app.scope.launch {
                    try {
                        app.backend.report(target, targetId, chosen, details)
                        sent = true
                    } catch (e: Exception) { error = e.userMessage } finally { isSending = false }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

/** A studio rates the artist after a completed session. Shown on the artist's profile; the artist can dispute it. */
@Composable
fun RateArtistSheet(booking: Booking, onSubmitted: () -> Unit = {}) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var rating by remember { mutableStateOf(5) }
    var text by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    NavScreen("", leading = { ToolbarButton("Later") { dismiss() } }, auroraHeight = 300.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            IconTile("star.bubble.fill", 44.dp, TilePalette.violet)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Txt(L10n.format("Rate %@", booking.artistName), style = Type.title3.heavy)
                Txt("${booking.sessionTypeName} · ${Dates.abbreviated(booking.startsAt)}", style = Type.caption, color = Theme.secondary)
            }
        }
        GlassCard(padding = 14.dp) { StarPicker("Overall", rating) { rating = it } }
        Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.78f), RoundedCornerShape(18.dp)).border(1.dp, Theme.primary.copy(alpha = 0.1f), RoundedCornerShape(18.dp)).padding(14.dp)) {
            PlainTextField(text, { text = it }, "How was the session? Punctual, respectful, prepared?", Modifier.fillMaxWidth(), minLines = 4, maxLines = 10)
        }
        T("Ratings are shown on the artist's profile with your studio name. Be fair: the artist can ask EasySesh to review it.", style = Type.caption, color = Theme.secondary)
        PrimaryButton(if (isSaving) "Sending…" else "Submit rating", enabled = !isSaving) {
            isSaving = true
            app.scope.launch {
                try {
                    app.backend.reviewArtist(booking.id, rating, text.trim())
                    onSubmitted()
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isSaving = false }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
