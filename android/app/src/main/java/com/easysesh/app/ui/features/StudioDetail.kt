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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.easysesh.app.AuthRoute
import com.easysesh.app.core.AvailabilityEngine
import com.easysesh.app.core.Dates
import com.easysesh.app.core.Distance
import com.easysesh.app.core.GeoPoint
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.TimeSlot
import com.easysesh.app.core.addingDays
import com.easysesh.app.core.startOfDay
import com.easysesh.app.core.tr
import com.easysesh.app.data.Backend
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.model.Conversation
import com.easysesh.app.model.EquipmentCategory
import com.easysesh.app.model.OpeningHours
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.Review
import com.easysesh.app.model.SocialLink
import com.easysesh.app.model.SocialPlatform
import com.easysesh.app.model.Studio
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.LocationService
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.launch
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.time.Instant

@Composable
fun StudioDetailView(studioId: String, initial: Studio?) {
    val app = LocalAppState.current
    val context = LocalContext.current
    val navigator = LocalNavigator.current
    val dismiss = LocalDismiss.current
    var studio by remember { mutableStateOf(initial) }
    var reviews by remember { mutableStateOf<List<Review>>(emptyList()) }
    var nextSlots by remember { mutableStateOf<List<TimeSlot>>(emptyList()) }
    var showBooking by remember { mutableStateOf(false) }
    var showReport by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    var linkedArtist by remember { mutableStateOf<ArtistProfile?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(studioId) {
        try {
            val loaded = app.backend.studio(studioId)
            studio = loaded
            val me = app.account?.id
            if (me != null && loaded.ownerId != me) {
                runCatching { app.backend.blockedUsers() }.getOrNull()?.let { list -> blocked = list.any { it.userId == loaded.ownerId } }
            }
            runCatching { app.backend.studioArtistLink(studioId) }.getOrNull()?.takeIf { it.isAccepted }?.let { link ->
                linkedArtist = runCatching { app.backend.artistProfile(link.artistId) }.getOrNull()
            }
            reviews = app.backend.reviews(studioId)
            nextSlots = nextSlots(loaded, app.backend)
        } catch (e: Exception) { error = e.userMessage }
    }

    fun startBooking() {
        if (app.account == null) app.guestAuthRequest = AuthRoute(AuthRoute.Mode.SignUp, UserRole.Artist) else showBooking = true
    }

    fun setBlocked(block: Boolean, s: Studio) {
        app.scope.launch {
            try {
                if (block) app.backend.blockStudio(s.id) else app.backend.unblockUser(s.ownerId)
                blocked = block
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    val current = studio
    Box(Modifier.fillMaxSize().background(Theme.background)) {
        if (current == null) {
            ProgressSpinner(Modifier.fillMaxSize())
        } else {
            Column(Modifier.fillMaxSize()) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    Gallery(current.photoUrls)
                    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        Header(current, linkedArtist)
                        if (nextSlots.isNotEmpty()) AvailabilitySection(nextSlots, current) { startBooking() }
                        PricingSection(current)
                        TextSection("About", current.description)
                        val video = current.videoUrl?.let { SocialLink.resolve(it, SocialPlatform.Youtube) }
                        val website = SocialLink.resolve(current.contact.website, SocialPlatform.Website)
                        if (video != null || website != null) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                video?.let { LinkChip("Studio tour", "play.rectangle.fill") { open(context, it) } }
                                website?.let { LinkChip("Website", "globe") { open(context, it) } }
                            }
                        }
                        FacilitiesSection(current)
                        EquipmentSection(current)
                        if (current.engineers.isNotEmpty()) PeopleSection(current)
                        GenresSection(current)
                        HoursSection(current)
                        RulesSection(current)
                        LocationSection(current)
                        ReviewsSection(current, reviews)
                        val me = app.account?.id
                        if (me != null && current.ownerId != me) {
                            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                                LabelButton("Report this studio", "flag") { showReport = true }
                                LabelButton(if (blocked) "Unblock" else "Block studio", if (blocked) "hand.raised.slash" else "hand.raised.fill") {
                                    if (blocked) setBlocked(false, current) else confirmBlock = true
                                }
                            }
                        }
                    }
                }
                BookingBar(current, onBook = { startBooking() }, onMessage = {
                    app.scope.launch {
                        try {
                            val conversation = app.backend.conversation(current.id, null)
                            navigator?.push { ChatView(conversation) }
                        } catch (e: Exception) { error = e.userMessage }
                    }
                })
            }
            if (showBooking) Sheet(onDismiss = { showBooking = false }) { BookingFlowView(current) }
            if (showReport) Sheet(onDismiss = { showReport = false }) { ReportSheet(ReportTarget.Studio, current.id) }
            if (confirmBlock) {
                ConfirmDialog(L10n.format("Block %@?", current.name), tr("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts."),
                    listOf(DialogAction("Block", destructive = true) { setBlocked(true, current) }), { confirmBlock = false }, translateTitle = false)
            }
        }
        Box(Modifier.statusBarsPadding().padding(12.dp)) { BackButton(dismiss) }
    }
    ErrorAlert(error) { error = null }
}

private fun open(context: android.content.Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

@Composable
private fun LabelButton(title: String, symbol: String, onClick: () -> Unit) {
    Row(Modifier.clip(RoundedCornerShape(8.dp)).pressable(onClick = onClick).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Sym(symbol, size = 15.dp, tint = Theme.secondary)
        T(title, style = Type.footnote, color = Theme.secondary)
    }
}

@Composable
private fun Header(studio: Studio, linkedArtist: ArtistProfile?) {
    val app = LocalAppState.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (studio.isPromoted) PromotedTag()
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Txt(studio.name, Modifier.weight(1f, fill = false), style = Type.display(32).tracking(-0.5f))
            if (studio.isVerified) VerifiedBadge()
            if (studio.showsAdminBadge) AdminBadge()
        }
        if (studio.specialTags.isNotEmpty()) FlowLayout(6.dp) { studio.specialTags.forEach { SpecialTagChip(it) } }
        if (linkedArtist != null) {
            NavLink({ ArtistPublicProfileView(linkedArtist.id, linkedArtist) }) {
                GlassCard(padding = 10.dp, cornerRadius = 18.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Avatar(linkedArtist.avatarUrl, linkedArtist.artistName, 34.dp, Modifier.border(1.5.dp, Theme.neon, CircleShape))
                        Column(Modifier.weight(1f)) {
                            Txt(tr("Run by").uppercase(), style = Type.caption2.bold, color = Theme.secondary)
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(linkedArtist.artistName, style = Type.subheadline.bold)
                                if (linkedArtist.hasAdminBadge == true) AdminBadge(compact = true)
                            }
                        }
                        Sym("chevron.right", size = 14.dp, tint = Theme.tertiary)
                    }
                }
            }
        }
        if (studio.tagline.isNotEmpty()) Txt(studio.tagline, style = Type.body, color = Theme.secondary)
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            RatingLabel(studio.ratingAverage, studio.reviewCount)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Sym("mappin", size = 15.dp, tint = Theme.accent)
                Txt(studio.address.publicArea, style = Type.subheadline)
            }
            if (app.location.isAuthorized) {
                Txt(Distance.format(app.location.effectiveLocation.distanceTo(GeoPoint(studio.latitude, studio.longitude))), style = Type.subheadline, color = Theme.secondary)
            }
        }
        FlowLayout(modifier = Modifier.padding(top = 4.dp)) {
            if (studio.bookingPolicy.instantBook) Chip("Instant book", "bolt.fill")
            Chip(L10n.format("Up to %lld people", studio.capacity), "person.2", translate = false)
            Chip(L10n.format("%lld sessions booked", studio.bookingCount), "calendar", translate = false)
        }
    }
}

@Composable
private fun AvailabilitySection(slots: List<TimeSlot>, studio: Studio, onBook: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Next available")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            slots.take(8).forEachIndexed { index, slot ->
                val shape = RoundedCornerShape(16.dp)
                Column(
                    Modifier
                        .then(if (index == 0) Modifier.neonGlow(Theme.magenta, 8.dp, shape) else Modifier)
                        .background(if (index == 0) Theme.neon else Brush.linearGradient(listOf(Theme.card.copy(alpha = 0.78f), Theme.card.copy(alpha = 0.78f))), shape)
                        .border(1.dp, if (index == 0) Color.Transparent else Theme.primary.copy(alpha = 0.1f), shape)
                        .pressable(onClick = onBook)
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    val color = if (index == 0) Color.White else Theme.primary
                    Txt(Dates.weekdayShortDay(slot.start, studio.zoneId), style = Type.caption.semibold, color = color.copy(alpha = 0.8f))
                    Txt(Dates.time(slot.start, studio.zoneId), style = Type.subheadline.heavy, color = color)
                }
            }
        }
    }
}

@Composable
private fun PricingSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Prices")
        studio.sessionTypes.forEach { type ->
            GlassCard(cornerRadius = Theme.corner) {
                Row {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(type.name, style = Type.body.semibold)
                            if (type.includesEngineer) Sym("person.wave.2", size = 16.dp, tint = Theme.accent)
                        }
                        if (type.details.isNotEmpty()) Txt(type.details, style = Type.footnote, color = Theme.secondary)
                        Txt(L10n.format("Min. %lldh", type.minimumHours), style = Type.caption, color = Theme.secondary)
                    }
                    Txt("${Money.format(type.hourlyRate, studio.currency)}/h", style = Type.body.bold)
                }
            }
        }
        if (studio.addOns.isNotEmpty()) {
            T("Add-ons", Modifier.padding(top = 4.dp), style = Type.headline)
            studio.addOns.forEach { addOn ->
                Row(Modifier.fillMaxWidth()) {
                    Txt(addOn.name, Modifier.weight(1f), style = Type.subheadline)
                    Txt("${Money.format(addOn.price, studio.currency)} ${tr(addOn.unit.suffix)}", style = Type.subheadline, color = Theme.secondary)
                }
            }
        }
        if (studio.bookingPolicy.depositPercent > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Sym("creditcard", size = 15.dp, tint = Theme.secondary)
                Txt(L10n.format("%lld%% deposit at booking, the rest is charged after your session.", studio.bookingPolicy.depositPercent), style = Type.footnote, color = Theme.secondary)
            }
        }
    }
}

@Composable
private fun LinkChip(title: String, symbol: String, onClick: () -> Unit) {
    Row(
        Modifier.background(Theme.card.copy(alpha = 0.78f), CircleShape).border(0.8.dp, Theme.colors.glassEdge, CircleShape).pressable(onClick = onClick).padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Sym(symbol, size = 16.dp, tint = Theme.accent)
        T(title, style = Type.subheadline.semibold)
    }
}

@Composable
private fun TextSection(title: String, text: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GlowSectionHeader(title)
        Txt(text, style = Type.body, color = Theme.secondary)
    }
}

@Composable
private fun FacilitiesSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Facilities")
        studio.facilities.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { facility ->
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Sym(facility.symbol, size = 17.dp, tint = Theme.accent)
                        T(facility.title, style = Type.subheadline)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun EquipmentSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Equipment")
        EquipmentCategory.entries.forEach { category ->
            val items = studio.equipment.filter { it.category == category }
            if (items.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    T(category.title, style = Type.subheadline.bold)
                    items.forEach { Txt("• ${it.name}", style = Type.subheadline, color = Theme.secondary) }
                }
            }
        }
    }
}

@Composable
private fun PeopleSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Engineers & producers")
        studio.engineers.forEach { person ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Avatar(null, person.name, 40.dp)
                Column {
                    Txt(person.name, style = Type.body.semibold)
                    Txt(person.role, style = Type.caption, color = Theme.accent)
                    if (person.bio.isNotEmpty()) Txt(person.bio, style = Type.caption, color = Theme.secondary)
                }
            }
        }
    }
}

@Composable
private fun GenresSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Genres")
        FlowLayout { studio.genres.forEach { Chip(it.title) } }
    }
}

@Composable
private fun HoursSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        GlowSectionHeader("Opening hours")
        OpeningHours.displayOrder.forEach { weekday ->
            studio.hours(weekday)?.let { hours ->
                Row(Modifier.fillMaxWidth()) {
                    Txt(hours.weekdayName, Modifier.weight(1f), style = Type.subheadline)
                    T(hours.label, style = Type.subheadline, color = if (hours.isClosed) Theme.secondary else Theme.primary)
                }
            }
        }
    }
}

@Composable
private fun RulesSection(studio: Studio) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GlowSectionHeader("Rules & terms")
        studio.rules.forEach { rule ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Sym("checkmark.circle", size = 17.dp, tint = Theme.accent)
                Txt(rule, style = Type.subheadline)
            }
        }
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Txt(L10n.format("Cancellation: %@", tr(studio.bookingPolicy.cancellationPolicy.title)), style = Type.subheadline.bold)
            T(studio.bookingPolicy.cancellationPolicy.summary, style = Type.footnote, color = Theme.secondary)
            if (studio.bookingPolicy.terms.isNotEmpty()) Txt(studio.bookingPolicy.terms, style = Type.footnote, color = Theme.secondary)
        }
    }
}

@Composable
private fun LocationSection(studio: Studio) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Location")
        AndroidView(
            modifier = Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(Theme.corner)),
            factory = {
                Configuration.getInstance().userAgentValue = context.packageName
                MapView(it).apply {
                    setTileSource(TileSourceFactory.MAPNIK)
                    setMultiTouchControls(false)
                    zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                    setOnTouchListener { _, _ -> true }
                    val point = org.osmdroid.util.GeoPoint(studio.latitude, studio.longitude)
                    controller.setZoom(15.0)
                    controller.setCenter(point)
                    overlays.add(Marker(this).apply { position = point; title = studio.name })
                }
            },
        )
        Txt(studio.address.publicArea, style = Type.subheadline)
        T("The exact address is shared after booking.", style = Type.caption, color = Theme.secondary)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PrimaryButton("Directions", Modifier.weight(1f), symbol = "arrow.triangle.turn.up.right.diamond.fill") { LocationService.openDirections(context, studio) }
            SecondaryButton("Google Maps", Modifier.weight(1f), symbol = "map") {
                open(context, "https://www.google.com/maps/search/?api=1&query=${studio.latitude},${studio.longitude}")
            }
        }
    }
}

@Composable
private fun ReviewsSection(studio: Studio, reviews: List<Review>) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        GlowSectionHeader("Reviews")
        ReviewSummaryView(studio, reviews)
        reviews.take(3).forEach { ReviewRow(it, canReply = false) }
        if (reviews.size > 3) {
            NavLink({ ReviewsListView(studio, reviews, canReply = false) }) {
                Txt(L10n.format("See all %lld reviews", reviews.size), style = Type.body.semibold, color = Theme.accent)
            }
        }
    }
}

@Composable
private fun BookingBar(studio: Studio, onBook: () -> Unit, onMessage: () -> Unit) {
    val app = LocalAppState.current
    Row(
        Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Txt(L10n.format("From %@/h", Money.format(studio.priceFrom, studio.currency)), style = Type.headline)
            T(if (studio.bookingPolicy.instantBook) "Instant confirmation" else "Studio confirms within 24h", style = Type.caption, color = Theme.secondary)
        }
        if (app.account == null) {
            PrimaryButton("Sign up to book", Modifier.width(160.dp)) { app.guestAuthRequest = AuthRoute(AuthRoute.Mode.SignUp, UserRole.Artist) }
        } else if (app.role == UserRole.Artist) {
            GlassIcon("bubble.left.fill", Modifier.pressable(onClick = onMessage))
            PrimaryButton("Book", Modifier.width(120.dp), onClick = onBook)
        }
    }
}

suspend fun nextSlots(studio: Studio, backend: Backend, days: Int = 7): List<TimeSlot> {
    val start = Instant.now().startOfDay
    val busy = runCatching { backend.busyIntervals(listOf(studio.id), start, start.addingDays(days + 1)) }.getOrNull()?.get(studio.id) ?: emptyList()
    val hours = studio.sessionTypes.minOfOrNull { it.minimumHours } ?: 1
    val engine = AvailabilityEngine()
    return (0 until days).flatMap { offset -> engine.availableSlots(studio, start.addingDays(offset), hours, busy).take(2) }
}

@Composable
fun Gallery(urls: List<String>) {
    val pages = if (urls.isEmpty()) listOf<String?>(null) else urls
    val pager = rememberPagerState { pages.size }
    Box(Modifier.fillMaxWidth().height(320.dp)) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { page -> RemoteImage(pages[page], Modifier.fillMaxSize()) }
        if (pages.size > 1) {
            Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                pages.indices.forEach { index ->
                    Box(Modifier.size(7.dp).background(if (index == pager.currentPage) Color.White else Color.White.copy(alpha = 0.45f), CircleShape))
                }
            }
        }
    }
}
