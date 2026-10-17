package com.easysesh.app.ui.features

import android.content.Intent
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.AvailabilityEngine
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.PlatformConfig
import com.easysesh.app.core.RefundCalculator
import com.easysesh.app.core.TimeSlot
import com.easysesh.app.core.addingDays
import com.easysesh.app.core.startOfDay
import com.easysesh.app.core.toLocalDate
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.Booking
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.CancellationPolicy
import com.easysesh.app.model.Interval
import com.easysesh.app.model.PaymentStatus
import com.easysesh.app.model.PaymentTransaction
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.Studio
import com.easysesh.app.model.TransactionKind
import com.easysesh.app.model.TransactionStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.DeepLink
import com.easysesh.app.services.LocationService
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import kotlin.math.roundToInt

private enum class SessionsMode(val title: String, val symbol: String) {
    Upcoming("Upcoming", "sparkles"), Calendar("Calendar", "calendar"), Past("Past", "clock.arrow.circlepath")
}

@Composable
fun ArtistBookingsView() {
    val app = LocalAppState.current
    var bookings by remember { mutableStateOf<List<Booking>>(emptyList()) }
    var mode by remember { mutableStateOf(SessionsMode.Upcoming) }
    var selectedDay by remember { mutableStateOf(LocalDate.now()) }
    var isLoading by remember { mutableStateOf(true) }
    var reviewing by remember { mutableStateOf<Booking?>(null) }
    val navigator = remember { Navigator() }
    val upcoming = bookings.filter { it.isUpcoming }.sortedBy { it.startsAt }

    suspend fun load() {
        runCatching { app.backend.artistBookings() }.getOrNull()?.let { bookings = it }
        isLoading = false
        app.syncReminders(bookings)
        (app.consumeDeepLink { it is DeepLink.BookingLink } as? DeepLink.BookingLink)?.let { link ->
            bookings.firstOrNull { it.id == link.id }?.let { b -> navigator.push { BookingDetailView(b.id, b) } }
        }
    }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(app.pendingDeepLink) { if (app.pendingDeepLink is DeepLink.BookingLink) load() }

    @Composable
    fun BookingCard(booking: Booking) {
        GlassCard(padding = 12.dp, onClick = { navigator.push { BookingDetailView(booking.id, booking) } }) { BookingRow(booking, UserRole.Artist) }
    }

    NavigationStack(navigator) {
        EasySeshScreen("Sessions", eyebrow = if (upcoming.isEmpty()) null else L10n.format("%lld coming up", upcoming.size), refresh = { load() }) {
            GlassSegmentedControl(mode, SessionsMode.entries, { it.title }, { it.symbol }) { mode = it }
            when (mode) {
                SessionsMode.Upcoming -> {
                    if (upcoming.isEmpty() && !isLoading) GlassEmptyState("No upcoming sessions", "calendar", "Find a studio and book your next session.")
                    upcoming.forEach { BookingCard(it) }
                }
                SessionsMode.Calendar -> {
                    MonthCalendar(selectedDay, { selectedDay = it }, bookings.filter { !it.status.isClosed || it.status == BookingStatus.Completed }.map { it.startsAt.toLocalDate() }.toSet())
                    val dayBookings = bookings.filter { it.startsAt.toLocalDate() == selectedDay }
                    if (dayBookings.isEmpty()) {
                        Txt(L10n.format("Nothing booked on %@.", Dates.abbreviated(selectedDay.atStartOfDay(ZoneId.systemDefault()).toInstant())),
                            Modifier.fillMaxWidth().padding(vertical = 8.dp), style = Type.subheadline, color = Theme.secondary, align = TextAlign.Center)
                    }
                    dayBookings.forEach { BookingCard(it) }
                }
                SessionsMode.Past -> {
                    val toReview = bookings.filter { it.canReview }
                    if (toReview.isNotEmpty()) {
                        GlowSectionHeader("Waiting for your review", toReview.size)
                        toReview.forEach { booking ->
                            GlassCard(padding = 12.dp, onClick = { reviewing = booking }) {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    IconTile("star.bubble.fill", 38.dp, TilePalette.signal)
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Txt(L10n.format("Review %@", booking.studioName), style = Type.subheadline.semibold)
                                        Txt(Dates.abbreviated(booking.startsAt), style = Type.caption, color = Theme.secondary)
                                    }
                                    Sym("chevron.right", size = 14.dp, tint = Theme.tertiary)
                                }
                            }
                        }
                    }
                    val history = bookings.filter { !it.isUpcoming }
                    GlowSectionHeader("History", history.size)
                    if (history.isEmpty() && !isLoading) GlassEmptyState("No past sessions", "clock.arrow.circlepath", "Sessions you've had show up here with receipts.")
                    history.forEach { BookingCard(it) }
                }
            }
        }
    }
    reviewing?.let { booking -> Sheet({ reviewing = null }) { WriteReviewView(booking) { app.scope.launch { load() } } } }
}

@Composable
fun BookingRow(booking: Booking, perspective: UserRole) {
    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.width(48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Txt(Dates.monthShort(booking.startsAt), style = Type.caption2.bold, color = Theme.accent)
            Txt(Dates.day(booking.startsAt), style = Type.title2.bold)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Txt(if (perspective == UserRole.Artist) booking.studioName else booking.artistName, style = Type.headline)
            Txt("${booking.sessionTypeName} · ${Dates.time(booking.startsAt)}–${Dates.time(booking.endsAt)}", style = Type.subheadline, color = Theme.secondary)
            StatusPill(booking.status.title, booking.status.color)
        }
        Txt(Money.format(if (perspective == UserRole.Artist) booking.price.total else booking.price.studioPayout, booking.price.currency), style = Type.subheadline.bold)
    }
}

@Composable
fun MonthCalendar(selectedDay: LocalDate, onSelect: (LocalDate) -> Unit, markedDays: Set<LocalDate>, blockedDays: Set<LocalDate> = emptySet()) {
    var month by remember { mutableStateOf(YearMonth.from(selectedDay)) }
    val locale = L10n.locale()
    val firstDay = WeekFields.of(java.util.Locale.getDefault()).firstDayOfWeek
    val weekdays = (0 until 7).map { firstDay.plus(it.toLong()) }
    GlassCard(padding = 14.dp, cornerRadius = 24.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                GlassIconButton("chevron.left", "Previous month") { month = month.minusMonths(1) }
                Txt(Dates.monthYear(month.atDay(1).atStartOfDay(ZoneId.systemDefault()).toInstant()), Modifier.weight(1f), style = Type.headline.bold, align = TextAlign.Center)
                GlassIconButton("chevron.right", "Next month") { month = month.plusMonths(1) }
            }
            Row {
                weekdays.forEach { day ->
                    Txt(day.getDisplayName(TextStyle.NARROW, locale), Modifier.weight(1f), style = Type.caption2.bold, color = Theme.secondary, align = TextAlign.Center)
                }
            }
            val leading = (month.atDay(1).dayOfWeek.value - firstDay.value + 7) % 7
            val cells: List<LocalDate?> = List(leading) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
            cells.chunked(7).forEach { week ->
                Row {
                    week.forEach { day ->
                        Box(Modifier.weight(1f).height(46.dp), contentAlignment = Alignment.Center) {
                            if (day != null) {
                                val isSelected = day == selectedDay
                                val isToday = day == LocalDate.now()
                                Column(Modifier.clickable { onSelect(day) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Box(
                                        Modifier.size(34.dp)
                                            .then(if (isSelected) Modifier.neonGlow(Theme.magenta, 8.dp, CircleShape).background(Theme.neon, CircleShape)
                                            else if (isToday) Modifier.border(1.5.dp, Theme.neon, CircleShape) else Modifier),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Txt("${day.dayOfMonth}", style = Type.subheadline.copy(fontWeight = if (isSelected || isToday) FontWeight.Bold else FontWeight.Normal),
                                            color = if (isSelected) Color.White else Theme.primary)
                                    }
                                    Row(Modifier.height(5.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                        if (day in markedDays) Box(Modifier.size(5.dp).background(Theme.neon, CircleShape))
                                        if (day in blockedDays) Box(Modifier.size(5.dp).background(Theme.red, CircleShape))
                                    }
                                }
                            }
                        }
                    }
                    repeat(7 - week.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

// MARK: Detail

private enum class BookingSheet { Cancel, Reschedule, Review, Dispute, Decline, ReportParty, RateArtist }

@Composable
fun BookingDetailView(bookingId: String, initial: Booking) {
    val app = LocalAppState.current
    val context = LocalContext.current
    val navigator = LocalNavigator.current
    var booking by remember { mutableStateOf(initial) }
    var transactions by remember { mutableStateOf<List<PaymentTransaction>>(emptyList()) }
    var studio by remember { mutableStateOf<Studio?>(null) }
    var sheet by remember { mutableStateOf<BookingSheet?>(null) }
    var isWorking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var ratedArtist by remember { mutableStateOf(false) }
    val isStudio = app.role == UserRole.StudioOwner
    val amountPaid = transactions.filter { it.status == TransactionStatus.Succeeded }.sumOf { if (it.kind == TransactionKind.Refund) -it.amount else it.amount }
    val feePercent = if (booking.price.subtotal > 0) (booking.price.studioCommission.toDouble() / booking.price.subtotal * 100).roundToInt() else PlatformConfig.PLATFORM_FEE_PERCENT

    suspend fun load() {
        try {
            booking = app.backend.booking(bookingId)
            transactions = app.backend.transactions(bookingId)
            if (studio == null) studio = runCatching { app.backend.studio(booking.studioId) }.getOrNull()
            if (isStudio && booking.status == BookingStatus.Completed) {
                runCatching { app.backend.artistReviews(booking.artistId) }.getOrNull()?.let { reviews -> ratedArtist = reviews.any { it.bookingId == booking.id } }
            }
        } catch (e: Exception) { error = e.userMessage }
    }
    LaunchedEffect(Unit) { load() }

    fun work(action: suspend () -> Unit) {
        isWorking = true
        app.scope.launch {
            try { action() } catch (e: Exception) { error = e.userMessage } finally { isWorking = false }
        }
    }

    NavScreen("Booking") {
        // Summary
        FormSection {
            FormContent {
                StatusPill(booking.status.title, booking.status.color)
                Txt(if (isStudio) booking.artistName else booking.studioName, style = Type.title2.bold)
                Txt(L10n.format("%@ · %lld hours", booking.sessionTypeName, booking.hours), style = Type.body, color = Theme.secondary)
            }
            FormRow { InfoRow("calendar", Dates.weekdayDayMonth(booking.startsAt), translateTitle = false) }
            FormRow { InfoRow("clock", "${Dates.time(booking.startsAt)} – ${Dates.time(booking.endsAt)}", translateTitle = false) }
            FormRow { InfoRow("number", "Reference", booking.reference) }
            val s = studio
            if (s != null && !isStudio && booking.status == BookingStatus.Confirmed) FormRow { InfoRow("mappin.and.ellipse", s.address.singleLine, translateTitle = false) }
            if (booking.notes.isNotEmpty()) FormRow { InfoRow("text.bubble", booking.notes, translateTitle = false) }
            booking.addOns.forEach { addOn ->
                FormRow { InfoRow("plus.circle", if (addOn.quantity > 1) "${addOn.name} × ${addOn.quantity}" else addOn.name, Money.format(addOn.amount, booking.price.currency), translateTitle = false) }
            }
            booking.cancellationReason?.let { FormRow { InfoRow("xmark.circle", "Reason", it) } }
        }
        // Check-in on arrival: optional, recommended against fraud.
        if (booking.status in listOf(BookingStatus.Confirmed, BookingStatus.Completed, BookingStatus.Disputed)) {
            val checkInOff = studio?.bookingPolicy?.checkInEnabled == false
            val footer = if (!checkInOff && booking.artistCheckedInAt == null && booking.status == BookingStatus.Confirmed) {
                if (isStudio) "Checking in records that the artist arrived. It protects both of you against fraud and helps EasySesh settle disputes."
                else "EasySesh recommends checking in when you arrive. It protects you against fraud and helps us settle any dispute. Your location is only used if you allow it."
            } else null
            FormSection("Check-in", footer = footer) {
                val checkedIn = booking.artistCheckedInAt
                when {
                    checkedIn != null -> FormRow {
                        IconTile("checkmark.seal.fill", 34.dp, TilePalette.mint)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T(if (isStudio) "Artist checked in" else "You checked in", style = Type.subheadline.semibold)
                            val time = Dates.abbreviatedWithTime(checkedIn)
                            val detail = booking.artistCheckInDistanceM?.let { d ->
                                val place = if (d < 1000) "$d m" else String.format(java.util.Locale.getDefault(), "%.1f km", d / 1000.0)
                                L10n.format("%@ · %@ from the studio", time, place)
                            } ?: time
                            Txt(detail, style = Type.caption, color = Theme.secondary)
                        }
                    }
                    checkInOff -> FormContent {
                        NoteLabel("exclamationmark.triangle.fill", tr(if (isStudio) "Check-in is turned off for your studio. EasySesh can't promise the artist a refund if something goes wrong."
                        else "This studio has turned off check-in. EasySesh can't promise a refund if something goes wrong with this session."), Theme.warning)
                    }
                    !isStudio && booking.canCheckIn() -> FormRow(onClick = {
                        work {
                            app.location.requestPermission()
                            val location = app.location.freshLocation()
                            booking = app.backend.checkIn(booking.id, location?.latitude, location?.longitude)
                        }
                    }) {
                        IconTile("location.circle.fill", 34.dp, TilePalette.signal)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T("Check in", style = Type.headline)
                            T("Tap when you've arrived at the studio", style = Type.caption, color = Theme.secondary)
                        }
                    }
                    booking.status == BookingStatus.Confirmed -> FormContent {
                        NoteLabel("clock", tr(if (isStudio) "The artist hasn't checked in yet." else "Check-in opens 1 hour before your session."), Theme.secondary)
                    }
                }
                val confirmedAt = booking.studioConfirmedArrivalAt
                if (confirmedAt != null) {
                    FormContent { NoteLabel("person.fill.checkmark", L10n.format(if (isStudio) "You confirmed the artist arrived · %@" else "The studio confirmed you arrived · %@", Dates.time(confirmedAt))) }
                } else if (isStudio && booking.status == BookingStatus.Confirmed && !booking.startsAt.minusSeconds(3600).isAfter(Instant.now())) {
                    FormButton("Confirm the artist arrived", "person.fill.checkmark") { work { booking = app.backend.confirmArrival(booking.id) } }
                }
            }
        }
        // Booking request (studio)
        if (isStudio && booking.status == BookingStatus.PendingApproval) {
            FormSection(footer = if (booking.isCash) "The artist will pay cash at the session." else "The artist's card is authorised. Accepting charges it; declining releases the hold.") {
                FormButton("Accept booking", "checkmark.circle.fill", enabled = !isWorking) {
                    work {
                        booking = app.backend.respondToBooking(booking.id, true, null)
                        transactions = app.backend.transactions(bookingId)
                    }
                }
                FormButton("Decline", "xmark.circle", color = Theme.red, enabled = !isWorking) { sheet = BookingSheet.Decline }
            }
        }
        // Actions
        FormSection("Actions") {
            FormButton(if (isStudio) "Message artist" else "Message studio", "bubble.left.and.bubble.right") {
                app.scope.launch {
                    try {
                        val conversation = app.backend.conversation(booking.studioId, booking.id)
                        navigator?.push { ChatView(conversation) }
                    } catch (e: Exception) { error = e.userMessage }
                }
            }
            val s = studio
            if (isStudio) {
                FormNavRow("View artist profile", "person.crop.circle") { ArtistPublicProfileView(booking.artistId, null) }
                if (booking.status == BookingStatus.Completed && !ratedArtist) FormButton("Rate the artist", "star.bubble") { sheet = BookingSheet.RateArtist }
            } else if (s != null) {
                FormNavRow("View studio", "building.2") { StudioDetailView(s.id, s) }
            }
            if (s != null && !isStudio && booking.status == BookingStatus.Confirmed) FormButton("Directions", "arrow.triangle.turn.up.right.diamond") { LocationService.openDirections(context, s) }
            if (booking.canReschedule) FormButton("Change date or time", "calendar.badge.clock") { sheet = BookingSheet.Reschedule }
            if (!isStudio && booking.canReview) FormButton("Write a review", "star.bubble") { sheet = BookingSheet.Review }
            if (booking.canCancel) FormButton("Cancel booking", "xmark.octagon", color = Theme.red) { sheet = BookingSheet.Cancel }
            if (booking.status in listOf(BookingStatus.Confirmed, BookingStatus.Completed)) FormButton("Report a problem", "exclamationmark.bubble") { sheet = BookingSheet.Dispute }
            FormButton(if (isStudio) "Report artist" else "Report studio", "flag") { sheet = BookingSheet.ReportParty }
            FormNavRow("Contact EasySesh support", "questionmark.circle") { SupportCenterView(booking) }
        }
        // Payment
        val paymentFooter = if (booking.isCash) {
            if (isStudio) L10n.format("Cash booking: collect %@ at the session. EasySesh's %lld%% fee is deducted from your next payout or invoiced.", Money.format(booking.price.total, booking.price.currency), feePercent)
            else L10n.format("Pay %@ in cash at the studio.", Money.format(booking.price.total, booking.price.currency)) + " " +
                tr("When you pay cash we cannot guarantee a refund, as EasySesh does not handle the cash. We will, however, look into it and try to help.")
        } else null
        FormSection("Payment", footer = paymentFooter, translate = false) {
            FormContent {
                if (isStudio) {
                    PriceRow("Session price", booking.price.subtotal, booking.price.currency)
                    Row(Modifier.fillMaxWidth()) {
                        Txt(L10n.format("EasySesh platform fee (%lld%%)", feePercent), Modifier.weight(1f), style = Type.body, color = Theme.secondary)
                        Txt(Money.format(-booking.price.studioCommission, booking.price.currency), style = Type.body, color = Theme.secondary)
                    }
                    PriceRow(if (booking.isCash) "Yours to keep" else "Your payout", booking.price.studioPayout, booking.price.currency, emphasized = true)
                } else {
                    PriceBreakdownView(booking.price)
                }
            }
            FormRow { InfoRow(if (booking.isCash) "banknote" else "creditcard", "Status", tr(booking.paymentStatus.title)) }
            if (isStudio && booking.isCash && booking.paymentStatus == PaymentStatus.PayAtStudio && !booking.startsAt.isAfter(Instant.now()) &&
                booking.status in listOf(BookingStatus.Confirmed, BookingStatus.Completed)) {
                FormButton("Mark cash as received", "checkmark.circle", enabled = !isWorking) { work { booking = app.backend.markCashReceived(booking.id) } }
            }
            if (booking.refundAmount > 0) FormRow { InfoRow("arrow.uturn.backward", "Refunded", Money.format(booking.refundAmount, booking.price.currency)) }
        }
        // Receipts
        if (transactions.isNotEmpty()) {
            FormSection("Receipts") {
                transactions.forEach { transaction ->
                    FormRow(onClick = { navigator?.push { ReceiptView(booking, transaction) } }) {
                        Column(Modifier.weight(1f)) {
                            T(when (transaction.kind) { TransactionKind.Refund -> "Refund"; TransactionKind.Balance -> "Balance payment"; else -> "Payment" }, style = Type.body)
                            Txt(Dates.abbreviatedWithTime(transaction.createdAt), style = Type.caption, color = Theme.secondary)
                        }
                        Txt((if (transaction.kind == TransactionKind.Refund) "−" else "") + Money.format(transaction.amount, transaction.currency), style = Type.body,
                            color = if (transaction.kind == TransactionKind.Refund) Theme.positive else Theme.primary)
                        Sym("chevron.right", size = 16.dp, tint = Theme.tertiary)
                    }
                }
            }
        }
    }
    when (sheet) {
        BookingSheet.Cancel -> Sheet({ sheet = null }) {
            CancelBookingSheet(booking, studio?.bookingPolicy?.cancellationPolicy ?: CancellationPolicy.Moderate, amountPaid, isStudio) { booking = it }
        }
        BookingSheet.Reschedule -> studio?.let { s -> Sheet({ sheet = null }) { RescheduleSheet(booking, s) { booking = it } } }
        BookingSheet.Review -> Sheet({ sheet = null }) { WriteReviewView(booking) { booking = booking.copy(hasReview = true) } }
        BookingSheet.Dispute -> Sheet({ sheet = null }) {
            TextPromptSheet("Report a problem", "What went wrong? Our team will review the booking and contact both sides.", "Send") { text ->
                app.backend.openDispute(booking.id, text)
                booking = booking.copy(status = BookingStatus.Disputed)
            }
        }
        BookingSheet.ReportParty -> Sheet({ sheet = null }) { ReportSheet(if (isStudio) ReportTarget.User else ReportTarget.Studio, if (isStudio) booking.artistId else booking.studioId) }
        BookingSheet.RateArtist -> Sheet({ sheet = null }) { RateArtistSheet(booking) { ratedArtist = true } }
        BookingSheet.Decline -> Sheet({ sheet = null }) {
            TextPromptSheet("Decline request", "Optional message to the artist", "Decline", allowEmpty = true) { text ->
                booking = app.backend.respondToBooking(booking.id, false, text.ifEmpty { null })
            }
        }
        null -> Unit
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun CancelBookingSheet(booking: Booking, policy: CancellationPolicy, amountPaid: Int, isStudio: Boolean, onCancelled: (Booking) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var reason by remember { mutableStateOf("") }
    var isWorking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val refund = if (booking.paymentStatus == PaymentStatus.Authorized) booking.price.dueNow
    else RefundCalculator.refundAmount(booking.price, amountPaid, policy, booking.startsAt, if (isStudio) UserRole.StudioOwner else UserRole.Artist)

    NavScreen("Cancel booking", leading = { ToolbarButton("Keep booking") { dismiss() } }, actions = {
        ToolbarButton("Cancel booking", enabled = !isWorking && !(isStudio && reason.isEmpty()), bold = true, color = Theme.red) {
            isWorking = true
            app.scope.launch {
                try {
                    onCancelled(app.backend.cancelBooking(booking.id, reason))
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isWorking = false }
            }
        }
    }) {
        FormSection(footer = if (isStudio) tr("When a studio cancels, the artist always gets a full refund. Frequent cancellations affect your listing.")
        else L10n.format("%@ policy: %@", tr(policy.title), tr(policy.summary)), translate = false) {
            FormContent {
                PriceRow("Paid so far", if (booking.paymentStatus == PaymentStatus.Authorized) 0 else amountPaid, booking.price.currency)
                PriceRow(if (isStudio) "Artist is refunded" else "You'll get back", refund, booking.price.currency, emphasized = true)
            }
        }
        FormSection("Reason") { FormTextField(if (isStudio) "Let the artist know why" else "Optional", reason, { reason = it }, minLines = 2, maxLines = 5) }
    }
    ErrorAlert(error) { error = null }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RescheduleSheet(booking: Booking, studio: Studio, onChanged: (Booking) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var day by remember { mutableStateOf(booking.startsAt.atZone(studio.zoneId).toLocalDate()) }
    var busy by remember { mutableStateOf<List<Interval>>(emptyList()) }
    var selected by remember { mutableStateOf<TimeSlot?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val dayInstant = day.atStartOfDay(studio.zoneId).toInstant()
    val slots = AvailabilityEngine().availableSlots(studio, dayInstant, booking.hours, busy.filter { it != booking.interval })
    LaunchedEffect(day) {
        selected = null
        busy = runCatching { app.backend.busyIntervals(listOf(studio.id), dayInstant.addingDays(-1), dayInstant.addingDays(2)) }.getOrNull()?.get(studio.id) ?: emptyList()
    }
    NavScreen("Change booking", leading = { ToolbarButton("Cancel") { dismiss() } }, actions = {
        ToolbarButton("Save", enabled = selected != null, bold = true) {
            val slot = selected ?: return@ToolbarButton
            app.scope.launch {
                try {
                    onChanged(app.backend.rescheduleBooking(booking.id, slot.start))
                    dismiss()
                } catch (e: Exception) { error = e.userMessage }
            }
        }
    }) {
        FormSection(footer = L10n.format("Same session type and length (%lld h). To change the length, cancel and book again.", booking.hours), translate = false) {
            val today = LocalDate.now(studio.zoneId)
            val state = rememberDatePickerState(
                initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
                selectableDates = object : SelectableDates {
                    override fun isSelectableDate(utcTimeMillis: Long) = !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(today)
                },
            )
            LaunchedEffect(state.selectedDateMillis) { state.selectedDateMillis?.let { day = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() } }
            DatePicker(state, title = null, headline = null, showModeToggle = false,
                colors = DatePickerDefaults.colors(containerColor = Color.Transparent, selectedDayContainerColor = Theme.accent, todayDateBorderColor = Theme.accent, todayContentColor = Theme.accent))
        }
        FormSection("New start time") {
            FormContent {
                if (slots.isEmpty()) T("No free slots this day.", style = Type.body, color = Theme.secondary)
                FlowLayout {
                    slots.forEach { slot ->
                        val isSelected = selected == slot
                        Txt(Dates.time(slot.start, studio.zoneId),
                            Modifier.background(if (isSelected) Theme.accent else Theme.fill, RoundedCornerShape(10.dp)).pressable { selected = slot }.padding(horizontal = 16.dp, vertical = 9.dp),
                            style = Type.subheadline.semibold, color = if (isSelected) Color.White else Theme.primary)
                    }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun TextPromptSheet(title: String, placeholder: String, action: String, allowEmpty: Boolean = false, onSubmit: suspend (String) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var text by remember { mutableStateOf("") }
    var isWorking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    NavScreen(title, leading = { ToolbarButton("Cancel") { dismiss() } }, actions = {
        ToolbarButton(action, enabled = !isWorking && (allowEmpty || text.trim().length >= 5), bold = true) {
            isWorking = true
            app.scope.launch {
                try {
                    onSubmit(text.trim())
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isWorking = false }
            }
        }
    }) {
        FormSection { FormTextField(placeholder, text, { text = it }, minLines = 4, maxLines = 10) }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun ReceiptView(booking: Booking, transaction: PaymentTransaction) {
    val context = LocalContext.current
    val title = tr(if (transaction.kind == TransactionKind.Refund) "Refund" else "Payment")
    val receiptText = """
        EasySesh receipt ${transaction.receiptNumber}
        $title: ${Money.format(transaction.amount, transaction.currency)}
        Date: ${Dates.abbreviatedWithTime(transaction.createdAt)}
        Studio: ${booking.studioName}
        Session: ${booking.sessionTypeName}, ${Dates.abbreviatedWithTime(booking.startsAt)}, ${booking.hours} h
        Booking ref: ${booking.reference}
    """.trimIndent()
    NavScreen("Receipt") {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            EasySeshLogo(20)
            T(if (transaction.kind == TransactionKind.Refund) "Refund receipt" else "Payment receipt", style = Type.headline)
            Txt(Money.format(transaction.amount, transaction.currency), style = Type.display(40))
        }
        FormSection {
            FormRow { InfoRow("number", "Receipt no.", transaction.receiptNumber) }
            FormRow { InfoRow("calendar", "Date", Dates.abbreviatedWithTime(transaction.createdAt)) }
            FormRow { InfoRow("creditcard", "Method", listOfNotNull(tr(transaction.method.title), transaction.cardBrand, transaction.cardLast4?.let { "•••• $it" }).joinToString(" ")) }
            FormRow { InfoRow("checkmark.circle", "Status", transaction.status.name) }
        }
        FormSection("Booking") {
            FormRow { InfoRow("building.2", booking.studioName, translateTitle = false) }
            FormRow { InfoRow("waveform", booking.sessionTypeName, "${booking.hours} h", translateTitle = false) }
            FormRow { InfoRow("calendar", Dates.abbreviatedWithTime(booking.startsAt), translateTitle = false) }
            FormRow { InfoRow("number", "Reference", booking.reference) }
        }
        if (transaction.kind == TransactionKind.Charge) FormSection("Breakdown") { FormContent { PriceBreakdownView(booking.price) } }
        FormSection(footer = "EasySesh acts as payment agent for the studio. The service fee includes VAT where applicable.") {
            FormButton("Share receipt", "square.and.arrow.up") {
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, receiptText), null))
            }
        }
    }
}

@Composable
fun BookingHistoryView() {
    val app = LocalAppState.current
    var bookings by remember { mutableStateOf<List<Booking>>(emptyList()) }
    LaunchedEffect(Unit) { bookings = runCatching { app.backend.artistBookings() }.getOrDefault(emptyList()) }
    NavScreen("Booking history") {
        if (bookings.isEmpty()) GlassEmptyState("No bookings yet", "clock")
        FormSection {
            bookings.forEach { booking ->
                FormNavRow(booking.studioName, translate = false, destination = { BookingDetailView(booking.id, booking) }) 
            }
        }
    }
}
