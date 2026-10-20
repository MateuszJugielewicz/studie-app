package com.easysesh.app.ui.features

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.core.AvailabilityEngine
import com.easysesh.app.core.Dates
import com.easysesh.app.core.EarningsCalculator
import com.easysesh.app.core.L10n
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.core.Money
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.BlockedSlot
import com.easysesh.app.model.Booking
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.FeeInvoice
import com.easysesh.app.model.FeeLedgerEntry
import com.easysesh.app.model.MonthlyAmount
import com.easysesh.app.model.Payout
import com.easysesh.app.model.PayoutStatus
import com.easysesh.app.model.Review
import com.easysesh.app.model.Studio
import com.easysesh.app.model.StudioStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.DeepLink
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

@Composable
fun StudioOwnerRootView() {
    val app = LocalAppState.current
    val studio = app.ownedStudio
    val account = app.account
    when {
        studio != null -> when (studio.status) {
            StudioStatus.Approved, StudioStatus.Suspended -> StudioTabView()
            else -> NavigationStack { ApplicationStatusView(studio) }
        }
        account != null -> NavigationStack {
            // An application may already exist (e.g. saved from another device); edit that instead of a new draft.
            LaunchedEffect(Unit) { runCatching { app.backend.ownedStudio() }.getOrNull()?.let { app.ownedStudio = it } }
            StudioEditorView(Studio.newDraft(account.id), isApplication = true, signOutInToolbar = true)
        }
    }
}

@Composable
fun ApplicationStatusView(studio: Studio) {
    val app = LocalAppState.current
    val navigator = LocalNavigator.current
    var isSubmitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        isSubmitting = true
        app.scope.launch {
            try { app.ownedStudio = app.backend.submitStudioForReview(studio.id) } catch (e: Exception) { error = e.userMessage }
            isSubmitting = false
        }
    }

    val statusText = when (studio.status) {
        StudioStatus.Draft -> "Finish your listing and submit it. Our team checks every studio before it becomes visible."
        StudioStatus.PendingReview -> "Thanks! We're reviewing your studio and will notify you, usually within 1–2 business days."
        StudioStatus.ChangesRequested -> "We need a few changes before we can approve your studio. Update your listing and resubmit."
        StudioStatus.Rejected -> "Unfortunately your studio wasn't approved. You can update your listing and apply again."
        else -> ""
    }

    EasySeshScreen("Application", eyebrow = studio.name.ifEmpty { tr("Your studio") },
        refresh = { runCatching { app.backend.ownedStudio() }.getOrNull()?.let { app.ownedStudio = it } }) {
        Box {
            GlassCard(padding = 18.dp, cornerRadius = 24.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    PulseDot(studio.status.color, studio.status == StudioStatus.PendingReview)
                    Txt(tr(studio.status.title).uppercase(L10n.locale()), style = Type.caption.heavy.tracking(0.8f), color = studio.status.color)
                }
                VSpace(14.dp)
                if (statusText.isNotEmpty()) T(statusText, style = Type.body)
            }
            Box(Modifier.align(Alignment.CenterStart).padding(vertical = 18.dp).width(4.dp).height(56.dp).background(Theme.neon, CircleShape))
        }
        val note = studio.adminNote
        if (!note.isNullOrEmpty()) {
            GlassCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                    IconTile("text.bubble.fill", 36.dp, listOf(Theme.warning, Theme.accent))
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        T("Message from the EasySesh team", style = Type.subheadline.bold)
                        Txt(note, style = Type.subheadline, color = Theme.secondary)
                    }
                }
            }
        }
        GlassCard(padding = 16.dp, cornerRadius = 24.dp) {
            ApplicationStep("Create your listing", done = true, isLast = false)
            ApplicationStep("Submit for review", done = studio.status != StudioStatus.Draft, isLast = false)
            ApplicationStep("EasySesh reviews your studio", done = studio.status == StudioStatus.Approved, active = studio.status == StudioStatus.PendingReview, isLast = false)
            ApplicationStep("Go live – artists can find, book and pay", done = studio.status == StudioStatus.Approved, isLast = true)
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (studio.status != StudioStatus.PendingReview) {
                PrimaryButton(if (isSubmitting) "Submitting…" else "Submit for review", Modifier.fillMaxWidth(), enabled = !isSubmitting, symbol = "paperplane.fill") { submit() }
            }
            SecondaryButton("Edit listing", Modifier.fillMaxWidth(), symbol = "pencil") { navigator?.push { StudioEditorView(studio, isApplication = true) } }
        }
        SignOutButton()
    }
    ErrorAlert(error) { error = null }
}

/** One row of the application timeline, with a gradient connector to the next step. */
@Composable
fun ApplicationStep(title: String, done: Boolean, active: Boolean = false, isLast: Boolean = true) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier.size(30.dp).neonGlow(Theme.magenta, 8.dp, CircleShape, active = done)
                    .background(if (done) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.08f), Theme.primary.copy(alpha = 0.08f))), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Sym(if (done) "checkmark" else if (active) "hourglass" else "circle.dotted", size = 14.dp,
                    tint = if (done) Color.White else if (active) Theme.warning else Theme.secondary)
            }
            if (!isLast) {
                Box(Modifier.width(2.dp).height(26.dp).background(if (done) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.1f), Theme.primary.copy(alpha = 0.1f)))))
            }
        }
        T(title, Modifier.padding(top = 5.dp), style = Type.subheadline.weight(if (done || active) FontWeight.Bold else FontWeight.Normal),
            color = if (done || active) Theme.primary else Theme.secondary)
    }
}

@Composable
fun StudioTabView() {
    val app = LocalAppState.current
    val preferences = app.preferences
    val studio = app.ownedStudio
    // The walkthrough plays once, the first time an approved studio opens the app.
    val showTour = studio != null && studio.status == StudioStatus.Approved && !preferences.hasCompletedTour(studio.id)
    val tour = remember(studio?.id, showTour) { if (showTour && studio != null) TabTour.studioApproved { preferences.completeTour(studio.id) } else null }
    EasySeshTabContainer(
        selection = app.selectedTab,
        onSelect = { app.selectTab(it) },
        tabs = listOf(
            TabSpec(AppTab.Dashboard, "Dashboard", "square.grid.2x2"),
            TabSpec(AppTab.Calendar, "Calendar", "calendar"),
            TabSpec(AppTab.Artists, "Artists", "music.mic"),
            TabSpec(AppTab.Messages, "Messages", "bubble.left.and.bubble.right", app.unreadMessages),
            TabSpec(AppTab.Notifications, "Inbox", "bell", app.unreadNotifications),
            TabSpec(AppTab.Profile, "Studio", "building.2"),
        ),
        resets = app.tabResetCounter,
        tour = tour,
    ) { tab ->
        when (tab) {
            AppTab.Calendar -> StudioCalendarView()
            AppTab.Artists -> FindArtistsView()
            AppTab.Messages -> ConversationsView()
            AppTab.Notifications -> NotificationsView()
            AppTab.Profile -> StudioSettingsView()
            else -> StudioDashboardView()
        }
    }
}

// MARK: Dashboard

class StudioDashboardModel {
    var bookings by mutableStateOf<List<Booking>>(emptyList())
    var payouts by mutableStateOf<List<Payout>>(emptyList())
    var reviews by mutableStateOf<List<Review>>(emptyList())
    var fees by mutableStateOf<List<FeeLedgerEntry>>(emptyList())

    suspend fun load(backend: com.easysesh.app.data.Backend, studioId: String) {
        runCatching { backend.studioBookings(studioId) }.getOrNull()?.let { bookings = it }
        runCatching { backend.payouts(studioId) }.getOrNull()?.let { payouts = it }
        runCatching { backend.reviews(studioId) }.getOrNull()?.let { reviews = it }
        runCatching { backend.feeLedger(studioId) }.getOrNull()?.let { fees = it }
    }

    /** Platform fees owed for cash bookings. */
    val feesOwed: Int get() = fees.sumOf { it.amount }
    val requests: List<Booking> get() = bookings.filter { it.status == BookingStatus.PendingApproval }.sortedBy { it.startsAt }
    val upcoming: List<Booking> get() = bookings.filter { it.status == BookingStatus.Confirmed && it.endsAt.isAfter(java.time.Instant.now()) }.sortedBy { it.startsAt }
    val past: List<Booking> get() = bookings.filter { !it.isUpcoming && it.status != BookingStatus.PendingApproval }
}

@Composable
fun StudioDashboardView() {
    val app = LocalAppState.current
    val model = remember { StudioDashboardModel() }
    val navigator = remember { Navigator() }

    suspend fun reload(studio: Studio) {
        model.load(app.backend, studio.id)
        runCatching { app.backend.ownedStudio() }.getOrNull()?.let { app.ownedStudio = it }
    }
    val studio = app.ownedStudio ?: return
    LaunchedEffect(studio.id) { reload(studio) }
    // Refresh when returning to the dashboard.
    LaunchedEffect(navigator.stack.size) { if (navigator.stack.isEmpty()) reload(studio) }

    NavigationStack(navigator) {
        EasySeshScreen(studio.name, eyebrow = greeting(), refresh = { reload(studio) }, trailing = {
            GlassIcon("eye", Modifier.pressable { navigator.push { StudioDetailView(studio.id, studio) } })
        }) {
            StoryBar()
            StudioDashboardContent(studio, model, navigator)
        }
    }
}

@Composable
private fun StudioDashboardContent(studio: Studio, model: StudioDashboardModel, navigator: Navigator) {
    val summary = EarningsCalculator.summary(model.bookings, model.payouts, studio.currency)
    if (studio.status == StudioStatus.Suspended) {
        GlassCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                IconTile("exclamationmark.octagon.fill", colors = listOf(Color.Red, Theme.magenta))
                T("Your studio is suspended and hidden from artists. Contact support.", style = Type.subheadline)
            }
        }
    }
    LiveToggleCard(studio)
    EarningsHeroCard(studio, summary.netThisMonth, summary.pendingPayout, summary.monthly)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StatCard("Upcoming", "${summary.upcomingSessions}", "calendar", TilePalette.ocean, Modifier.weight(1f))
        StatCard("Requests", "${model.requests.size}", "tray.and.arrow.down", TilePalette.signal, Modifier.weight(1f))
        StatCard("Rating", if (studio.reviewCount == 0) "–" else String.format(Locale.getDefault(), "%.1f", studio.ratingAverage), "star.fill", TilePalette.violet, Modifier.weight(1f))
    }
    if (model.feesOwed > 0) {
        GlassCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                IconTile("banknote", colors = TilePalette.violet)
                Txt(L10n.format("You owe %@ in platform fees for cash bookings. It's deducted from your next payout.", Money.format(model.feesOwed, studio.currency)), style = Type.footnote)
            }
        }
    }
    if (model.requests.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            GlowSectionHeader("Requests", model.requests.size)
            model.requests.forEach { booking ->
                Box {
                    GlassCard(padding = 12.dp, onClick = { navigator.push { BookingDetailView(booking.id, booking) } }) { BookingRow(booking, UserRole.StudioOwner) }
                    Box(Modifier.align(Alignment.CenterStart).width(3.dp).height(40.dp).background(Theme.neon, CircleShape))
                }
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Upcoming")
        if (model.upcoming.isEmpty()) GlassEmptyState("No upcoming sessions", "calendar.badge.clock", "New bookings show up here the moment artists book.")
        model.upcoming.take(5).forEach { booking ->
            GlassCard(padding = 12.dp, onClick = { navigator.push { BookingDetailView(booking.id, booking) } }) { BookingRow(booking, UserRole.StudioOwner) }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlowSectionHeader("Manage")
        GlassCard(padding = 0.dp) {
            ManageLink("Earnings & payouts", "chart.bar.fill", TilePalette.mint) { EarningsView(studio, model.bookings, model.payouts, model.fees) }
            Divider(Modifier.padding(start = 60.dp))
            ManageLink("Past bookings", "clock.arrow.circlepath", TilePalette.ocean) { StudioBookingListView("Past bookings", model.past) }
            Divider(Modifier.padding(start = 60.dp))
            ManageLink("Prices & services", "tag.fill", TilePalette.signal) { StudioSectionEditor("Prices & services") { s, set -> StudioPricingEditor(s, set) } }
            Divider(Modifier.padding(start = 60.dp))
            ManageLink("Opening hours", "clock.fill", TilePalette.violet) {
                StudioSectionEditor("Opening hours") { s, set -> OpeningHoursEditor(s.openingHours) { set(s.copy(openingHours = it)) } }
            }
            Divider(Modifier.padding(start = 60.dp))
            ManageLink("Reviews", "star.bubble.fill", listOf(Theme.warning, Theme.accent), model.reviews.size) { ReviewsListView(studio, model.reviews, canReply = true) }
        }
    }
}

/** Neon card with this month's earnings and a six-month trend line. */
@Composable
private fun EarningsHeroCard(studio: Studio, netThisMonth: Int, pendingPayout: Int, monthly: List<MonthlyAmount>) {
    val shape = RoundedCornerShape(26.dp)
    Column(
        Modifier.fillMaxWidth().neonGlow(Theme.magenta, 20.dp, shape).clip(shape).background(Theme.neon)
            .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.22f), 0.5f to Color.Transparent))
            .border(0.8.dp, Color.White.copy(alpha = 0.3f), shape).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            T("Earned this month", Modifier.weight(1f), style = Type.subheadline.semibold, color = Color.White.copy(alpha = 0.85f))
            Sym("waveform", size = 15.dp, tint = Color.White.copy(alpha = 0.8f))
        }
        Txt(Money.format(netThisMonth, studio.currency), style = Type.system(40, FontWeight.ExtraBold), color = Color.White, maxLines = 1)
        TrendLine(monthly.map { it.amount.toFloat() }, Modifier.fillMaxWidth().height(64.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Sym("arrow.down.circle.fill", size = 13.dp, tint = Color.White)
            Txt(L10n.format("Next payout %@", Money.format(pendingPayout, studio.currency)), Modifier.weight(1f), style = Type.caption.semibold, color = Color.White)
            Txt(L10n.format("%lld%% platform fee", studio.feePercent), style = Type.caption.semibold, color = Color.White.copy(alpha = 0.75f))
        }
    }
}

/** Smooth white area + line chart (iOS Charts AreaMark/LineMark with catmullRom). */
@Composable
private fun TrendLine(values: List<Float>, modifier: Modifier) {
    Canvas(modifier) {
        if (values.isEmpty()) return@Canvas
        val maxValue = values.max().coerceAtLeast(1f)
        val stepX = if (values.size > 1) size.width / (values.size - 1) else 0f
        val points = values.mapIndexed { i, v -> Offset(i * stepX, size.height - 3f - (v / maxValue) * (size.height - 6f)) }
        val line = Path().apply {
            moveTo(points[0].x, points[0].y)
            for (i in 1 until points.size) {
                val p0 = points[i - 1]
                val p1 = points[i]
                val midX = (p0.x + p1.x) / 2
                cubicTo(midX, p0.y, midX, p1.y, p1.x, p1.y)
            }
        }
        val area = Path().apply {
            addPath(line)
            lineTo(points.last().x, size.height)
            lineTo(points.first().x, size.height)
            close()
        }
        drawPath(area, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.45f), Color.White.copy(alpha = 0f))))
        drawPath(line, Color.White, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
    }
}

/** Monthly bar chart with month labels (Earnings screen). */
@Composable
private fun MonthlyBars(monthly: List<MonthlyAmount>) {
    val accent = Theme.accent
    val maxValue = (monthly.maxOfOrNull { it.amount } ?: 0).coerceAtLeast(1)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.fillMaxWidth().height(160.dp)) {
            val slot = size.width / monthly.size.coerceAtLeast(1)
            val barWidth = slot * 0.6f
            monthly.forEachIndexed { i, item ->
                val h = (item.amount.toFloat() / maxValue) * size.height
                drawRoundRect(accent, Offset(i * slot + (slot - barWidth) / 2, size.height - h), Size(barWidth, h), CornerRadius(4.dp.toPx()))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            monthly.forEach { item -> Txt(Dates.monthShort(item.month), Modifier.weight(1f), style = Type.caption2, color = Theme.secondary, align = androidx.compose.ui.text.style.TextAlign.Center) }
        }
    }
}

/** Wraps a section editor with a save button bound to the owned studio. */
@Composable
fun StudioSectionEditor(title: String, content: @Composable (Studio, (Studio) -> Unit) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var draft by remember { mutableStateOf(app.ownedStudio) }
    var error by remember { mutableStateOf<String?>(null) }
    NavScreen(title, actions = {
        ToolbarButton("Save", bold = true) {
            val toSave = draft ?: return@ToolbarButton
            app.scope.launch {
                try {
                    app.ownedStudio = app.backend.saveStudio(toSave)
                    dismiss()
                } catch (e: Exception) { error = e.userMessage }
            }
        }
    }) {
        val current = draft
        if (current == null) Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { ProgressSpinner() }
        else content(current) { draft = it }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun ManageLink(title: String, symbol: String, colors: List<Color> = TilePalette.signal, badge: Int = 0, destination: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    Row(
        Modifier.fillMaxWidth().pressable { navigator?.push(destination) }.padding(horizontal = 14.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(symbol, 32.dp, colors)
        T(title, Modifier.weight(1f), style = Type.body.weight(FontWeight.Medium))
        if (badge > 0) Txt("$badge", style = Type.subheadline, color = Theme.secondary)
        Sym("chevron.right", size = 13.dp, tint = Theme.tertiary)
    }
}

@Composable
fun LiveToggleCard(studio: Studio) {
    val app = LocalAppState.current
    var error by remember { mutableStateOf<String?>(null) }
    GlassCard {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            PulseDot(Theme.positive, studio.isActive)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                T(if (studio.isActive) "Live on EasySesh" else "Paused", style = Type.headline)
                T(if (studio.isActive) "Artists can find and book you." else "Hidden from search. Existing bookings are kept.", style = Type.caption, color = Theme.secondary)
            }
            Switch(
                studio.isActive,
                { value ->
                    app.scope.launch {
                        try { app.ownedStudio = app.backend.setStudioActive(studio.id, value) } catch (e: Exception) { error = e.userMessage }
                    }
                },
                enabled = studio.status == StudioStatus.Approved,
                colors = SwitchDefaults.colors(checkedTrackColor = Theme.positive, checkedThumbColor = Color.White, uncheckedTrackColor = Theme.fill, uncheckedBorderColor = Color.Transparent, uncheckedThumbColor = Color.White),
            )
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun StudioBookingListView(title: String, bookings: List<Booking>) {
    NavScreen(title) {
        if (bookings.isEmpty()) GlassEmptyState("Nothing here yet", "calendar")
        else FormSection {
            bookings.forEach { booking ->
                val navigator = LocalNavigator.current
                FormRow(onClick = { navigator?.push { BookingDetailView(booking.id, booking) } }) {
                    Box(Modifier.weight(1f)) { BookingRow(booking, UserRole.StudioOwner) }
                    Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
                }
            }
        }
    }
}

// MARK: Calendar

@Composable
fun StudioCalendarView() {
    val app = LocalAppState.current
    var bookings by remember { mutableStateOf<List<Booking>>(emptyList()) }
    var blocked by remember { mutableStateOf<List<BlockedSlot>>(emptyList()) }
    var selectedDay by remember { mutableStateOf(LocalDate.now()) }
    var showBlock by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val navigator = remember { Navigator() }
    val zone = ZoneId.systemDefault()

    fun openDeepLink() {
        val link = app.consumeDeepLink { it is DeepLink.BookingLink } as? DeepLink.BookingLink ?: return
        bookings.firstOrNull { it.id == link.id }?.let { booking ->
            selectedDay = booking.startsAt.atZone(zone).toLocalDate()
            navigator.push { BookingDetailView(booking.id, booking) }
        }
    }

    suspend fun load() {
        val studio = app.ownedStudio ?: return
        runCatching { app.backend.studioBookings(studio.id) }.getOrNull()?.let { bookings = it }
        runCatching { app.backend.blockedSlots(studio.id) }.getOrNull()?.let { blocked = it }
        openDeepLink()
    }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(app.pendingDeepLink) { openDeepLink() }

    fun unblock(slot: BlockedSlot) {
        app.scope.launch {
            try {
                app.backend.removeBlockedSlot(slot.id)
                blocked = blocked.filter { it.id != slot.id }
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavigationStack(navigator) {
        val dayInstant = selectedDay.atStartOfDay(zone).toInstant()
        EasySeshScreen("Calendar", eyebrow = Dates.weekdayDayMonth(dayInstant), refresh = { load() }, trailing = {
            GlassIconButton("nosign", "Block time") { showBlock = true }
        }) {
            MonthCalendar(
                selectedDay, { selectedDay = it },
                bookings.filter { it.status.isActive || it.status == BookingStatus.Completed }.map { it.startsAt.atZone(zone).toLocalDate() }.toSet(),
                blocked.map { it.startsAt.atZone(zone).toLocalDate() }.toSet(),
            )
            val studio = app.ownedStudio
            if (studio != null) {
                AnimatedContent(selectedDay, transitionSpec = { (fadeIn() + slideInVertically { it / 6 }) togetherWith fadeOut() }, label = "day") { day ->
                    val start = day.atStartOfDay(zone).toInstant()
                    val window = AvailabilityEngine().openingWindow(studio, start)
                    val dayBookings = bookings.filter { it.startsAt.atZone(zone).toLocalDate() == day && it.status != BookingStatus.Expired }
                    val dayBlocks = blocked.filter { it.startsAt.atZone(zone).toLocalDate() == day }
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.weight(1f)) { GlowSectionHeader(Dates.weekdayDayMonth(start).substringBeforeLast(' '), dayBookings.size) }
                            Row(
                                Modifier.background(Theme.card.copy(alpha = 0.6f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
                                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
                            ) {
                                if (window != null) {
                                    Sym("clock", size = 12.dp)
                                    Txt("${Dates.time(window.start)}–${Dates.time(window.end)}", style = Type.caption.semibold)
                                } else {
                                    Sym("moon.zzz.fill", size = 12.dp, tint = Theme.secondary)
                                    T("Closed", style = Type.caption.semibold, color = Theme.secondary)
                                }
                            }
                        }
                        if (dayBookings.isEmpty() && dayBlocks.isEmpty()) {
                            GlassEmptyState("Nothing booked", "sparkles", if (window == null) "The studio is closed this day." else "This day is wide open for sessions.")
                        }
                        dayBookings.forEach { booking ->
                            GlassCard(padding = 12.dp, onClick = { navigator.push { BookingDetailView(booking.id, booking) } }) {
                                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Box(Modifier.width(4.dp).fillMaxHeight().background(Theme.neon, CircleShape))
                                    Box(Modifier.weight(1f)) { BookingRow(booking, UserRole.StudioOwner) }
                                }
                            }
                        }
                        dayBlocks.forEach { slot ->
                            GlassCard(padding = 12.dp) {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    IconTile("nosign", 34.dp, listOf(Color.Red, Theme.magenta))
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        if (slot.reason.isEmpty()) T("Blocked", style = Type.subheadline.semibold) else Txt(slot.reason, style = Type.subheadline.semibold)
                                        Txt("${Dates.time(slot.startsAt)} – ${Dates.time(slot.endsAt)}", style = Type.caption, color = Theme.secondary)
                                    }
                                    T("Unblock", Modifier.clip(RoundedCornerShape(8.dp)).background(Theme.red.copy(alpha = 0.15f)).pressable { unblock(slot) }
                                        .padding(horizontal = 10.dp, vertical = 6.dp), style = Type.caption.semibold, color = Theme.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (showBlock) {
        app.ownedStudio?.let { studio ->
            Sheet({ showBlock = false }) { BlockTimeSheet(studio.id, selectedDay) { blocked = blocked + it } }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun BlockTimeSheet(studioId: String, day: LocalDate, onAdded: (BlockedSlot) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val zone = ZoneId.systemDefault()
    var startDate by remember { mutableStateOf(day) }
    var startMinutes by remember { mutableStateOf(12 * 60) }
    var endDate by remember { mutableStateOf(day) }
    var endMinutes by remember { mutableStateOf(14 * 60) }
    var allDay by remember { mutableStateOf(false) }
    var reason by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    fun block() {
        val from = if (allDay) startDate.atStartOfDay(zone).toInstant() else startDate.atStartOfDay(zone).plusMinutes(startMinutes.toLong()).toInstant()
        val to = if (allDay) startDate.plusDays(1).atStartOfDay(zone).toInstant() else endDate.atStartOfDay(zone).plusMinutes(endMinutes.toLong()).toInstant()
        app.scope.launch {
            try {
                onAdded(app.backend.addBlockedSlot(BlockedSlot(UUID.randomUUID().toString(), studioId, from, maxOf(from, to), reason)))
                dismiss()
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen(
        "Block time",
        leading = { ToolbarButton("Cancel") { dismiss() } },
        actions = { ToolbarButton("Block", bold = true) { block() } },
    ) {
        FormSection {
            FormToggle("All day", allDay) { allDay = it }
            FormRow {
                T("From", Modifier.weight(1f), style = Type.body)
                DateButton(startDate) { startDate = it; if (endDate.isBefore(it)) endDate = it }
                if (!allDay) TimeButton(startMinutes) { startMinutes = it }
            }
            if (!allDay) {
                FormRow {
                    T("To", Modifier.weight(1f), style = Type.body)
                    DateButton(endDate, min = startDate) { endDate = it }
                    TimeButton(endMinutes) { endMinutes = it }
                }
            }
            FormTextField("Reason (private)", reason, { reason = it })
        }
    }
    ErrorAlert(error) { error = null }
}

// MARK: Earnings

@Composable
fun EarningsView(studio: Studio, bookings: List<Booking>, payouts: List<Payout>, fees: List<FeeLedgerEntry> = emptyList()) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var invoices by remember { mutableStateOf<List<FeeInvoice>>(emptyList()) }
    LaunchedEffect(Unit) { runCatching { app.backend.feeInvoices(studio.id) }.getOrNull()?.let { invoices = it } }
    val summary = EarningsCalculator.summary(bookings, payouts, studio.currency)

    NavScreen("Earnings") {
        FormSection {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                T("Earned this month", style = Type.caption, color = Theme.secondary)
                Txt(Money.format(summary.netThisMonth, studio.currency), style = Type.largeTitle.bold)
                Txt(L10n.format("%@ booked · %lld%% platform fee", Money.format(summary.grossThisMonth, studio.currency), studio.feePercent), style = Type.caption, color = Theme.secondary)
                VSpace(12.dp)
                MonthlyBars(summary.monthly)
            }
        }

        FormSection("Totals") {
            FormRow { InfoRow("sum", "All-time earnings", Money.format(summary.netAllTime, studio.currency)) }
            FormRow { InfoRow("checkmark.circle", "Completed sessions", "${summary.completedSessions}") }
            FormRow { InfoRow("clock", "Hours booked", "${summary.hoursBooked}") }
            FormRow { InfoRow("hourglass", "Upcoming payouts", Money.format(summary.pendingPayout, studio.currency)) }
        }

        FormSection("Payouts") {
            if (payouts.isEmpty()) FormRow { T("Payouts appear here after your first completed session.", style = Type.body, color = Theme.secondary) }
            payouts.forEach { payout ->
                FormRow {
                    Column(Modifier.weight(1f)) {
                        Txt(Money.format(payout.amount, payout.currency), style = Type.headline)
                        Txt(
                            if (payout.status == PayoutStatus.Paid) L10n.format("Paid %@", Dates.abbreviated(payout.paidAt ?: payout.scheduledFor))
                            else L10n.format("Expected %@", Dates.abbreviated(payout.scheduledFor)),
                            style = Type.caption, color = Theme.secondary,
                        )
                    }
                    StatusPill(tr(payout.status.title), when (payout.status) { PayoutStatus.Paid -> Theme.positive; PayoutStatus.Failed -> Theme.red; else -> Theme.warning })
                }
            }
        }

        FormSection("Cash bookings & platform fees", footer = L10n.format("For cash bookings you collect the full price; EasySesh's %lld%% fee is deducted from your next payout. Anything left is invoiced monthly and must be paid within 14 days. Unpaid invoices lead to suspension from EasySesh and debt collection.", studio.feePercent), translate = false) {
            FormRow { InfoRow("banknote", "Platform fees owed", Money.format(maxOf(fees.sumOf { it.amount }, 0), studio.currency)) }
            fees.forEach { entry ->
                FormRow {
                    Column(Modifier.weight(1f)) {
                        T(entry.kind.title, style = Type.body)
                        Txt(Dates.abbreviated(entry.createdAt), style = Type.caption, color = Theme.secondary)
                    }
                    Txt(Money.format(entry.amount, entry.currency), style = Type.body, color = if (entry.amount < 0) Theme.positive else Theme.primary)
                }
            }
        }

        if (invoices.isNotEmpty()) {
            val overdue = invoices.any { it.isOverdue || it.isInCollections }
            FormSection("Invoices", footer = if (overdue) "You have an overdue invoice. Pay it now to avoid suspension and debt collection. Contact support if you think this is a mistake." else null, footerColor = Theme.red) {
                invoices.forEach { invoice ->
                    FormRow {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Txt(Money.format(invoice.amount, invoice.currency), style = Type.headline)
                            invoice.dueAt?.let { due -> Txt(L10n.format("Due %@", Dates.abbreviated(due)), style = Type.caption, color = if (invoice.isOverdue) Theme.red else Theme.secondary) }
                        }
                        val link = invoice.hostedInvoiceUrl
                        if (link != null && invoice.status != "paid") {
                            LinkButton("Pay", style = Type.subheadline.bold) { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) } }
                        }
                        StatusPill(tr(invoice.statusTitle), if (invoice.status == "paid") Theme.positive else if (invoice.isOverdue || invoice.isInCollections) Theme.red else Theme.warning)
                    }
                }
            }
        }

        FormSection {
            FormNavRow("Payout details", "building.columns") { PayoutAccountEditor(studio.id) }
            FormNavRow("Studio agreement", "doc.text") { LegalDocumentView(LegalDocument.StudioAgreement) }
        }
    }
}

// MARK: Studio settings tab

@Composable
fun StudioSettingsView() {
    val app = LocalAppState.current
    val navigator = remember { Navigator() }
    NavigationStack(navigator) {
        EasySeshScreen("Studio", eyebrow = tr("Your listing"), refresh = { runCatching { app.backend.ownedStudio() }.getOrNull()?.let { app.ownedStudio = it } }) {
            val studio = app.ownedStudio
            if (studio != null) {
                StudioCover(studio) { navigator.push { StudioDetailView(studio.id, studio) } }
                GlassCard(padding = 12.dp) {
                    Row(Modifier.height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
                        QuickStat(if (studio.reviewCount == 0) "–" else String.format(Locale.getDefault(), "%.1f", studio.ratingAverage), "Rating")
                        Box(Modifier.width(0.5.dp).height(30.dp).background(Theme.stroke))
                        QuickStat("${studio.reviewCount}", "Reviews")
                        Box(Modifier.width(0.5.dp).height(30.dp).background(Theme.stroke))
                        QuickStat("${studio.bookingCount}", "Bookings")
                        Box(Modifier.width(0.5.dp).height(30.dp).background(Theme.stroke))
                        QuickStat(Money.format(studio.priceFrom, studio.currency), "From / h")
                    }
                }
                if (studio.status == StudioStatus.Approved && !studio.isVerified) VerificationCard("studio")
                ProfileTileGrid(listOf(
                    ProfileTile("Edit profile", "Photos, gear, rooms", "pencil", TilePalette.signal) { StudioEditorView(studio, isApplication = false) },
                    ProfileTile("Prices", "Sessions & add-ons", "tag.fill", TilePalette.violet) { StudioSectionEditor("Prices & services") { s, set -> StudioPricingEditor(s, set) } },
                    ProfileTile("Opening hours", "When you're bookable", "clock.fill", TilePalette.ocean) {
                        StudioSectionEditor("Opening hours") { s, set -> OpeningHoursEditor(s.openingHours) { set(s.copy(openingHours = it)) } }
                    },
                    ProfileTile("Booking settings", if (studio.bookingPolicy.instantBook) "Instant booking" else "You approve (24h)", "bolt.fill", listOf(Theme.warning, Theme.accent)) {
                        StudioSectionEditor("Booking settings") { s, set -> StudioPolicyEditor(s, set) }
                    },
                    ProfileTile("Offers & codes", "Discounts for artists", "percent", listOf(Theme.warning, Theme.accent)) { StudioOffersView(studio) },
                    ProfileTile("Promotion", if (studio.isPromoted) "Promoted now" else "Not promoted", "megaphone.fill", TilePalette.signal) { PromotionView(studio) },
                    ProfileTile("Artist profiles", "Owners & team", "link", TilePalette.violet) { StudioArtistLinkView(studio) },
                    ProfileTile("Payouts", "Bank details", "building.columns.fill", TilePalette.mint) { PayoutAccountEditor(studio.id) },
                    ProfileTile("Account", "Notifications & data", "person.crop.circle.fill", TilePalette.muted) { SettingsView() },
                    ProfileTile("App settings", "Language, look, storage", "slider.horizontal.3", TilePalette.ocean) { AppSettingsView() },
                    ProfileTile("Support", "Talk to EasySesh", "questionmark.bubble.fill", listOf(Theme.warning, Theme.accent)) { SupportCenterView() },
                    ProfileTile("Agreement", "Studio terms", "doc.text.fill", TilePalette.muted) { LegalDocumentView(LegalDocument.StudioAgreement) },
                ))
            } else {
                GlassCard(onClick = { navigator.push { SettingsView() } }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Sym("gearshape")
                        T("Account & notifications", style = Type.body)
                    }
                }
            }
            SignOutButton()
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.QuickStat(value: String, title: String) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Txt(value, style = Type.headline.heavy, maxLines = 1)
        T(title, style = Type.caption2.weight(FontWeight.Medium), color = Theme.secondary, maxLines = 1)
    }
}

@Composable
private fun StudioCover(studio: Studio, onClick: () -> Unit) {
    val shape = RoundedCornerShape(26.dp)
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 10f).shadow(20.dp, shape).clip(shape).border(0.8.dp, Theme.stroke, shape).pressable(onClick = onClick)) {
        RemoteImage(studio.photoUrls.firstOrNull(), Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f))))
        Column(Modifier.align(Alignment.BottomStart).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                Modifier.background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                PulseDot(Theme.positive, studio.isActive)
                Txt(tr(if (studio.isActive) "Live" else studio.status.title).uppercase(L10n.locale()), style = Type.caption.bold.tracking(0.8f), color = Color.White)
            }
            if (studio.isPromoted) PromotedTag()
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(studio.name, style = Type.title2.heavy, color = Color.White, maxLines = 1)
                if (studio.isVerified) VerifiedBadge()
                if (studio.showsAdminBadge) AdminBadge()
            }
            Txt(studio.address.publicArea, style = Type.subheadline, color = Color.White.copy(alpha = 0.85f))
        }
        Row(
            Modifier.align(Alignment.TopEnd).padding(12.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            Sym("eye.fill", size = 12.dp, tint = Color.White)
            T("Preview", style = Type.caption.semibold, color = Color.White)
        }
    }
}
