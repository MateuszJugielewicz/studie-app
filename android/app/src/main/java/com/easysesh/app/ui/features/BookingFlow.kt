package com.easysesh.app.ui.features

import android.content.Intent
import android.provider.CalendarContract
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.core.AvailabilityEngine
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.PlatformConfig
import com.easysesh.app.core.PricingEngine
import com.easysesh.app.core.TimeSlot
import com.easysesh.app.core.addingDays
import com.easysesh.app.core.addingHours
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.Booking
import com.easysesh.app.model.BookingRequest
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.Interval
import com.easysesh.app.model.PriceBreakdown
import com.easysesh.app.model.PriceUnit
import com.easysesh.app.model.PromoCheck
import com.easysesh.app.model.StudioOffer
import com.easysesh.app.model.ServiceAddOn
import com.easysesh.app.model.Studio
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class BookingDraft(val studio: Studio) {
    var sessionTypeId by mutableStateOf(studio.sessionTypes.firstOrNull()?.id ?: "")
    var hours by mutableStateOf(studio.sessionTypes.firstOrNull()?.minimumHours ?: 2)
    var day by mutableStateOf(LocalDate.now(studio.zoneId))
    var selectedSlot by mutableStateOf<TimeSlot?>(null)
    var addOns by mutableStateOf(mapOf<String, Int>())
    var notes by mutableStateOf("")
    var busy by mutableStateOf<List<Interval>>(emptyList())
    var isLoadingSlots by mutableStateOf(false)
    var offers by mutableStateOf<List<StudioOffer>>(emptyList())
    /** The server's price for [quoteKey] (offers applied); the local quote is shown until it arrives. */
    private var serverQuote by mutableStateOf<Pair<String, PriceBreakdown>?>(null)
    private val engine = AvailabilityEngine()

    val dayInstant: Instant get() = day.atStartOfDay(studio.zoneId).toInstant()
    val sessionType get() = studio.sessionType(sessionTypeId)
    val slots: List<TimeSlot> get() = engine.availableSlots(studio, dayInstant, hours, busy)
    val quoteKey: String get() = "$sessionTypeId|$hours|" + addOns.filter { it.value > 0 }.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
    val quote: PriceBreakdown?
        get() = serverQuote?.takeIf { it.first == quoteKey }?.second ?: sessionType?.let { PricingEngine.quote(studio, it, hours, addOns) }

    suspend fun refreshQuote(backend: com.easysesh.app.data.Backend) {
        val key = quoteKey
        kotlinx.coroutines.delay(200)
        runCatching { backend.quoteBooking(studio, sessionTypeId, hours, addOns) }.getOrNull()?.let { serverQuote = key to it }
    }
    val request: BookingRequest?
        get() {
            val type = sessionType ?: return null
            val slot = selectedSlot ?: return null
            return BookingRequest(studio, type, slot.start, hours, addOns, notes)
        }

    suspend fun loadBusy(backend: com.easysesh.app.data.Backend) {
        isLoadingSlots = true
        try {
            val start = dayInstant.addingDays(-1)
            busy = runCatching { backend.busyIntervals(listOf(studio.id), start, start.addingDays(3)) }.getOrNull()?.get(studio.id) ?: emptyList()
            selectedSlot?.let { selected -> if (slots.none { it.start == selected.start }) selectedSlot = null }
        } finally {
            isLoadingSlots = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookingFlowView(studio: Studio) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val navigator = LocalNavigator.current
    val draft = remember { BookingDraft(studio) }
    LaunchedEffect(draft.day) { draft.loadBusy(app.backend) }
    LaunchedEffect(draft.quoteKey) { draft.refreshQuote(app.backend) }
    LaunchedEffect(Unit) { draft.offers = runCatching { app.backend.studioOffers(studio.id) }.getOrDefault(emptyList()) }
    LaunchedEffect(draft.sessionTypeId) {
        val minimum = draft.sessionType?.minimumHours
        if (minimum != null && draft.hours < minimum) draft.hours = minimum
    }
    LaunchedEffect(draft.hours) {
        draft.selectedSlot?.let { selected -> draft.selectedSlot = draft.slots.firstOrNull { it.start == selected.start } }
    }

    NavScreen(
        studio.name, translateTitle = false,
        leading = { ToolbarButton("Close") { dismiss() } },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().padding(16.dp)) {
                PrimaryButton(
                    if (draft.selectedSlot == null) tr("Pick a time") else L10n.format("Continue · %@", Money.format(draft.quote?.total ?: 0, studio.currency)),
                    enabled = draft.request != null, translate = false,
                ) { draft.request?.let { request -> navigator?.push { CheckoutView(request) { dismiss() } } } }
            }
        },
    ) {
        StudioOffersSection(studio, draft.offers)
        FormSection("Session type") {
            FormInlinePicker(draft.sessionTypeId, studio.sessionTypes.map { it.id }, { id ->
                val type = studio.sessionType(id)!!
                "${type.name} · ${Money.format(type.hourlyRate, studio.currency)}/h"
            }) { draft.sessionTypeId = it }
        }
        FormSection("Duration") {
            FormRow {
                Txt(L10n.format("%lld hours", draft.hours), Modifier.weight(1f), style = Type.body.bold)
                Stepper(draft.hours, (draft.sessionType?.minimumHours ?: 1)..PlatformConfig.MAX_SESSION_HOURS) { draft.hours = it }
            }
        }
        FormSection("Date") {
            val today = LocalDate.now(studio.zoneId)
            val last = today.plusDays(studio.bookingPolicy.maxAdvanceDays.toLong())
            val state = rememberDatePickerState(
                initialSelectedDateMillis = draft.day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
                selectableDates = object : SelectableDates {
                    override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                        val d = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                        return !d.isBefore(today) && !d.isAfter(last)
                    }
                },
            )
            LaunchedEffect(state.selectedDateMillis) {
                state.selectedDateMillis?.let { draft.day = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }
            }
            DatePicker(state, title = null, headline = null, showModeToggle = false,
                colors = DatePickerDefaults.colors(containerColor = Color.Transparent, selectedDayContainerColor = Theme.accent, todayDateBorderColor = Theme.accent, todayContentColor = Theme.accent))
        }
        FormSection("Start time", footerContent = {
            draft.selectedSlot?.let { slot ->
                Txt("${Dates.weekdayDayMonth(slot.start, studio.zoneId)} ${Dates.time(slot.start, studio.zoneId)} – ${Dates.time(slot.end, studio.zoneId)}", style = Type.footnote, color = Theme.secondary)
            }
        }) {
            FormContent {
                when {
                    draft.isLoadingSlots -> CircularProgressIndicator(Modifier.size(22.dp), color = Theme.accent, strokeWidth = 2.dp)
                    draft.slots.isEmpty() -> Txt(
                        if (AvailabilityEngine().openingWindow(studio, draft.dayInstant) == null) tr("The studio is closed this day.")
                        else L10n.format("No free %lld-hour slots this day. Try fewer hours or another date.", draft.hours),
                        style = Type.body, color = Theme.secondary,
                    )
                    else -> FlowLayout {
                        draft.slots.forEach { slot ->
                            val selected = draft.selectedSlot == slot
                            Txt(
                                Dates.time(slot.start, studio.zoneId),
                                Modifier.background(if (selected) Theme.accent else Theme.background, RoundedCornerShape(10.dp))
                                    .pressable { draft.selectedSlot = slot }.padding(horizontal = 18.dp, vertical = 10.dp),
                                style = Type.subheadline.semibold, color = if (selected) Color.White else Theme.primary,
                            )
                        }
                    }
                }
            }
        }
        if (studio.addOns.isNotEmpty()) {
            FormSection("Add-ons") {
                studio.addOns.forEach { addOn ->
                    AddOnRow(addOn, studio.currency, draft.addOns[addOn.id] ?: 0) { draft.addOns = draft.addOns + (addOn.id to it) }
                }
            }
        }
        FormSection("Notes for the studio") {
            FormTextField("What are you working on? Anything they should prepare?", draft.notes, { draft.notes = it }, minLines = 2, maxLines = 5)
        }
        draft.quote?.let { quote ->
            FormSection("Price") { FormContent { PriceBreakdownView(quote) } }
        }
    }
}

@Composable
fun AddOnRow(addOn: ServiceAddOn, currency: String, quantity: Int, onChange: (Int) -> Unit) {
    FormRow {
        Column(Modifier.weight(1f)) {
            Txt(addOn.name, style = Type.body)
            Txt("${Money.format(addOn.price, currency)} ${tr(addOn.unit.suffix)}", style = Type.caption, color = Theme.secondary)
            if (addOn.unit == PriceUnit.PerTrack && quantity > 0) {
                Txt(if (quantity == 1) tr("1 track") else L10n.format("%lld tracks", quantity), style = Type.caption, color = Theme.accent)
            }
        }
        if (addOn.unit == PriceUnit.PerTrack) Stepper(quantity, 0..20, onChange)
        else androidx.compose.material3.Switch(quantity > 0, { onChange(if (it) 1 else 0) },
            colors = androidx.compose.material3.SwitchDefaults.colors(checkedTrackColor = Theme.positive, checkedThumbColor = Color.White))
    }
}

@Composable
fun PriceBreakdownView(price: PriceBreakdown) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Txt("${Money.format(price.hourlyRate, price.currency)} × ${price.hours} h", Modifier.weight(1f), style = Type.body, color = Theme.secondary)
            Txt(Money.format(price.sessionAmount, price.currency), style = Type.body, color = Theme.secondary)
        }
        if (price.addOnsAmount > 0) PriceRow("Add-ons", price.addOnsAmount, price.currency)
        price.discounts.forEach { discount ->
            Row(Modifier.fillMaxWidth()) {
                val title = if (discount.kind == "offer") discount.label else L10n.format("Code %@", discount.label)
                Txt("$title (−${discount.percent}%)", Modifier.weight(1f), style = Type.body, color = Theme.positive)
                Txt("−" + Money.format(discount.amount, price.currency), style = Type.body, color = Theme.positive)
            }
        }
        if (price.serviceFee > 0) PriceRow("Service fee", price.serviceFee, price.currency)
        Divider()
        PriceRow("Total", price.total, price.currency, emphasized = true)
        if (price.depositAmount > 0) {
            PriceRow(if (price.serviceFee > 0) "Due now (deposit + fee)" else "Due now (deposit)", price.dueNow, price.currency)
            PriceRow("Charged after the session", price.dueLater, price.currency)
        }
    }
}

// MARK: Checkout

@Composable
fun CheckoutView(request: BookingRequest, onFinish: () -> Unit) {
    val app = LocalAppState.current
    val payments = LocalPaymentLauncher.current
    val navigator = LocalNavigator.current
    val studio = request.studio
    val cardAvailable = payments.isAvailable
    val cashAvailable = PricingEngine.acceptsCash(studio)
    var payWithCash by remember { mutableStateOf(!cardAvailable && cashAvailable) }
    var agreed by remember { mutableStateOf(false) }
    var isPaying by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var codeInput by remember { mutableStateOf("") }
    var promo by remember { mutableStateOf<PromoCheck?>(null) }
    var checkingCode by remember { mutableStateOf(false) }
    var serverPrice by remember { mutableStateOf<PriceBreakdown?>(null) }
    LaunchedEffect(promo?.code) {
        serverPrice = runCatching { app.backend.quoteBooking(studio, request.sessionType.id, request.hours, request.addOns, promo?.code) }.getOrNull()
    }
    val price = serverPrice ?: PricingEngine.quote(studio, request.sessionType, request.hours, request.addOns)

    fun applyCode() {
        val code = codeInput.trim().uppercase()
        if (code.isEmpty()) return
        checkingCode = true
        app.scope.launch {
            runCatching { app.backend.checkPromoCode(studio.id, code) }
                .onSuccess { promo = it; codeInput = "" }
                .onFailure { error = it.userMessage }
            checkingCode = false
        }
    }
    val amount = Money.format(price.dueNow, price.currency)
    val payTitle = when {
        payWithCash && studio.bookingPolicy.instantBook -> tr("Book · pay cash at the studio")
        payWithCash -> tr("Request to book · pay cash")
        studio.bookingPolicy.instantBook -> L10n.format("Pay %@", amount)
        else -> L10n.format("Request to book · %@", amount)
    }
    val zone = studio.zoneId

    fun pay() {
        isPaying = true
        app.scope.launch {
            try {
                val booking = app.backend.createBooking(request.copy(promoCode = promo?.code))
                val confirmed = if (payWithCash) app.backend.confirmCashBooking(booking.id) else {
                    val intent = app.backend.preparePayment(booking.id)
                    if (payments.pay(intent) == PaymentOutcome.Cancelled) null else app.backend.confirmPayment(booking.id)
                }
                if (confirmed != null) {
                    app.refreshBadges()
                    navigator?.push { BookingConfirmationView(confirmed, onFinish) }
                }
            } catch (e: Exception) {
                error = e.userMessage
            } finally {
                isPaying = false
            }
        }
    }

    NavScreen("Checkout", bottomBar = {
        Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().padding(16.dp), contentAlignment = Alignment.Center) {
            PrimaryButton(if (isPaying) "" else payTitle, enabled = agreed && !isPaying && (payWithCash || cardAvailable), translate = false) { pay() }
            if (isPaying) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
        }
    }) {
        FormSection("Your session") {
            FormContent {
                InfoRow("building.2", studio.name, translateTitle = false)
                InfoRow("waveform", request.sessionType.name, "${request.hours} h", translateTitle = false)
                InfoRow("calendar", Dates.abbreviated(request.startsAt, zone), "${Dates.time(request.startsAt, zone)} – ${Dates.time(request.startsAt.addingHours(request.hours), zone)}", translateTitle = false)
            }
        }
        FormSection("Payment") { FormContent { PriceBreakdownView(price) } }
        FormSection("Promo code", footer = promo?.description?.takeIf { it.isNotEmpty() }, translate = false) {
            val applied = promo
            if (applied != null) {
                FormRow {
                    Txt("${applied.code} · −${applied.percentOff}%", Modifier.weight(1f), style = Type.body.semibold, color = Theme.positive)
                    androidx.compose.material3.TextButton(onClick = { promo = null }) { T("Remove", color = Theme.red) }
                }
            } else {
                FormRow {
                    PlainTextField(codeInput, { value -> codeInput = value.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }.take(20) }, "Enter a code", Modifier.weight(1f),
                        capitalization = KeyboardCapitalization.Characters)
                    androidx.compose.material3.TextButton(onClick = { applyCode() }, enabled = codeInput.isNotBlank() && !checkingCode) { T("Apply", color = Theme.accent) }
                }
            }
        }
        if (cashAvailable && cardAvailable) {
            FormSection("How do you want to pay?", footer = if (payWithCash) L10n.format("Bring %@ in cash to your session. Paying in the app gives you automatic refunds under the cancellation policy.", Money.format(price.total, price.currency)) else null, translate = true) {
                FormInlinePicker(payWithCash, listOf(false, true), { if (it) "Pay cash at the studio" else "Pay now in the app" }, { if (it) "banknote" else "creditcard" }) { payWithCash = it }
            }
        }
        FormSection {
            FormContent {
                when {
                    payWithCash -> {
                        NoteLabel("banknote", L10n.format("Pay %@ in cash at the session.", Money.format(price.total, price.currency)))
                        NoteLabel("exclamationmark.triangle", tr("When you pay cash we cannot guarantee a refund, as EasySesh does not handle the cash. We will, however, look into it and try to help."), Theme.warning)
                    }
                    cardAvailable -> NoteLabel("lock.shield", tr("Card or Google Pay – securely processed by Stripe."))
                    else -> NoteLabel("exclamationmark.circle", tr("In-app payment isn't available yet, and this studio doesn't accept cash. Message the studio to arrange your session."), Theme.warning)
                }
            }
        }
        FormSection(footer = if (!studio.bookingPolicy.instantBook) (if (payWithCash) "This studio confirms requests manually, within 24 hours." else "This studio confirms requests manually, within 24 hours. Your card is authorised now and only charged if they accept.") else null) {
            FormRow {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Txt(L10n.format("I agree to the studio's rules and the %@ cancellation policy.", tr(studio.bookingPolicy.cancellationPolicy.title).lowercase()), style = Type.footnote)
                    T(studio.bookingPolicy.cancellationPolicy.summary, style = Type.caption, color = Theme.secondary)
                }
                androidx.compose.material3.Switch(agreed, { agreed = it }, colors = androidx.compose.material3.SwitchDefaults.colors(checkedTrackColor = Theme.positive, checkedThumbColor = Color.White))
            }
        }
        FormSection {
            FormContent {
                if (studio.bookingPolicy.checkInEnabled) {
                    NoteLabel("location.circle", tr("Check in in the app when you arrive. EasySesh recommends it: it protects you against fraud and helps us sort out any problem."))
                } else {
                    NoteLabel("exclamationmark.triangle", tr("This studio has turned off check-in. EasySesh can't promise a refund if something goes wrong with this session."), Theme.warning)
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun NoteLabel(symbol: String, text: String, color: Color = Theme.primary) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Sym(symbol, size = 16.dp, tint = if (color == Theme.primary) Theme.accent else color)
        Txt(text, style = Type.footnote, color = color)
    }
}

@Composable
fun BookingConfirmationView(booking: Booking, onDone: () -> Unit) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var addedToCalendar by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { app.syncReminders(listOf(booking)) }
    val confirmed = booking.status == BookingStatus.Confirmed
    NavScreen("", leading = {}) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Sym(if (confirmed) "checkmark.circle.fill" else "clock.badge.checkmark.fill", Modifier.padding(top = 32.dp), size = 72.dp, tint = if (confirmed) Theme.positive else Theme.warning)
            T(if (confirmed) "You're booked!" else "Request sent", style = Type.largeTitle.bold)
            val message = if (confirmed) {
                if (booking.isCash) L10n.format("Pay %@ in cash at the studio. We'll remind you before your session.", Money.format(booking.price.total, booking.price.currency))
                else tr("We've sent a confirmation and receipt. We'll remind you before your session.")
            } else L10n.format("%@ will respond within 24 hours.", booking.studioName) + (if (booking.isCash) "" else " " + tr("You're only charged if they accept."))
            Txt(message, style = Type.body, color = Theme.secondary, align = TextAlign.Center)
            GlassCard(cornerRadius = Theme.corner) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    InfoRow("number", "Reference", booking.reference)
                    InfoRow("building.2", booking.studioName, translateTitle = false)
                    InfoRow("calendar", Dates.weekdayDayMonth(booking.startsAt), translateTitle = false)
                    InfoRow("clock", "${Dates.time(booking.startsAt)} – ${Dates.time(booking.endsAt)}", translateTitle = false)
                    InfoRow(if (booking.isCash) "banknote" else "creditcard", booking.paymentStatus.title,
                        Money.format(if (booking.isCash) booking.price.total else booking.price.dueNow, booking.price.currency))
                }
            }
            SecondaryButton(if (addedToCalendar) "Added to calendar" else "Add to calendar", symbol = if (addedToCalendar) "checkmark" else "calendar.badge.plus", enabled = !addedToCalendar) {
                CalendarExporter.add(context, booking)
                addedToCalendar = true
            }
            PrimaryButton("Done") {
                app.selectedTab = AppTab.Bookings
                onDone()
            }
        }
    }
}

object CalendarExporter {
    /** Opens the phone's calendar with the session filled in (no calendar permission needed). */
    fun add(context: android.content.Context, booking: Booking) {
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, "${booking.sessionTypeName} · ${booking.studioName}")
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, booking.startsAt.toEpochMilli())
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, booking.endsAt.toEpochMilli())
            .putExtra(CalendarContract.Events.DESCRIPTION, L10n.format("EasySesh booking %@", booking.reference))
        runCatching { context.startActivity(intent) }
    }
}

/** The studio's live offers ("Mixing 50% off"), on the booking screen and the studio page. */
@Composable
fun StudioOffersSection(studio: Studio, offers: List<StudioOffer>) {
    val live = offers.filter { it.isLive }
    if (live.isEmpty()) return
    FormSection("Offers") {
        live.forEach { offer -> FormRow { OfferRowContent(offer, studio) } }
    }
}

@Composable
fun androidx.compose.foundation.layout.RowScope.OfferRowContent(offer: StudioOffer, studio: Studio) {
    Column(Modifier.weight(1f)) {
        Txt(offer.title, style = Type.subheadline.semibold)
        val until = offer.endsAt?.let { " · " + L10n.format("Until %@", Dates.abbreviated(it, studio.zoneId)) } ?: ""
        Txt(L10n.format("%lld%% off · %@", offer.percentOff, offerTargetName(offer, studio)) + until, style = Type.caption, color = Theme.secondary)
    }
    Box(Modifier.clip(androidx.compose.foundation.shape.RoundedCornerShape(8.dp)).background(Theme.positive).padding(horizontal = 8.dp, vertical = 3.dp)) {
        Txt("−${offer.percentOff}%", style = Type.caption.bold, color = Color.White)
    }
}

fun offerTargetName(offer: StudioOffer, studio: Studio): String = when (offer.appliesTo) {
    "sessions" -> tr("All sessions")
    "add_ons" -> tr("All extras")
    "session_type" -> studio.sessionTypes.firstOrNull { it.id == offer.targetId }?.name ?: tr("Session")
    "add_on" -> studio.addOns.firstOrNull { it.id == offer.targetId }?.name ?: tr("Extra")
    else -> tr("Everything")
}
