package com.easysesh.app.ui.features

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.easysesh.app.core.ImageCompressor
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.PlatformConfig
import com.easysesh.app.core.StudioValidator
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.AddOnKind
import com.easysesh.app.model.CancellationPolicy
import com.easysesh.app.model.EquipmentCategory
import com.easysesh.app.model.EquipmentItem
import com.easysesh.app.model.Facility
import com.easysesh.app.model.Genre
import com.easysesh.app.model.OpeningHours
import com.easysesh.app.model.PayoutAccount
import com.easysesh.app.model.PriceUnit
import com.easysesh.app.model.ServiceAddOn
import com.easysesh.app.model.SessionType
import com.easysesh.app.model.Studio
import com.easysesh.app.model.StudioPerson
import com.easysesh.app.services.LocationService
import com.easysesh.app.services.StripeBankTokenizer
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.util.UUID

/**
 * The studio being edited, shared by the editor and its sections (iOS passes a Binding<Studio>
 * down to each sub-editor).
 */
private class StudioDraft(initial: Studio) {
    var studio by mutableStateOf(initial)
}

private fun newId() = UUID.randomUUID().toString().lowercase()

/** Create or edit a studio listing. Used for the application and for later edits. */
@Composable
fun StudioEditorView(initial: Studio, isApplication: Boolean, signOutInToolbar: Boolean = false, onSaved: (Studio) -> Unit = {}) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val draft = remember(initial.id) { StudioDraft(initial) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val studio = draft.studio
    val set: (Studio) -> Unit = { draft.studio = it }

    fun save() {
        isSaving = true
        app.scope.launch {
            try {
                val saved = app.backend.saveStudio(draft.studio)
                draft.studio = saved
                app.ownedStudio = saved
                onSaved(saved)
                if (!isApplication) dismiss()
            } catch (e: Exception) {
                error = e.userMessage
                // If the application was stored after all, show it instead of this unsaved draft.
                if (isApplication) runCatching { app.backend.ownedStudio() }.getOrNull()?.let { app.ownedStudio = it }
            }
            isSaving = false
        }
    }

    /** Stores the application as a draft (not submitted) so its payout account can be linked to it. */
    val saveDraft: suspend () -> Unit = { draft.studio = app.backend.saveStudio(draft.studio) }

    NavScreen(
        if (isApplication) "Studio application" else "Edit studio",
        leading = if (signOutInToolbar) ({ ToolbarButton("Sign out") { app.scope.launch { app.signOut() } } }) else null,
        actions = { ToolbarButton(if (isSaving) "Saving…" else "Save", enabled = !isSaving, bold = true) { save() } },
    ) {
        if (isApplication) {
            Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                T("List your studio", style = Type.title2.bold)
                T("Fill in each section. When you're ready, submit your studio for review – our team usually replies within 1–2 business days.", style = Type.body, color = Theme.secondary)
            }
        }

        FormSection("Your listing") {
            EditorLink("Basics & photos", "photo.on.rectangle", !studio.name.isEmpty() && studio.photoUrls.isNotEmpty() && studio.description.length >= 40) {
                StudioBasicsEditor(draft.studio, set)
            }
            EditorLink("Address & contact", "mappin.and.ellipse", studio.address.city.isNotEmpty() && studio.latitude != 0.0) {
                StudioLocationEditor(draft.studio, set)
            }
            EditorLink("Prices & services", "eurosign.circle", studio.sessionTypes.isNotEmpty()) {
                NavScreen("Prices & services") { StudioPricingEditor(draft.studio, set) }
            }
            EditorLink("Opening hours", "clock", !studio.openingHours.all { it.isClosed }) {
                NavScreen("Opening hours") { OpeningHoursEditor(draft.studio.openingHours) { set(draft.studio.copy(openingHours = it)) } }
            }
            EditorLink("Facilities, gear & genres", "slider.vertical.3", studio.genres.isNotEmpty() && studio.facilities.isNotEmpty()) {
                StudioFeaturesEditor(draft.studio, set)
            }
            EditorLink("Booking settings & rules", "bolt.fill", true) {
                NavScreen("Booking settings") { StudioPolicyEditor(draft.studio, set) }
            }
            EditorLink("Payout details", "building.columns", true) {
                // A new application isn't stored yet; save the draft before talking to Stripe.
                PayoutAccountEditor(studio.id, if (isApplication) saveDraft else null)
            }
        }

        val problems = StudioValidator.problems(studio)
        if (isApplication && problems.isNotEmpty()) {
            FormSection("Still missing") {
                problems.forEach { problem ->
                    FormRow {
                        Sym("exclamationmark.circle", size = 16.dp, tint = Theme.warning)
                        T(problem, Modifier.weight(1f), style = Type.footnote, color = Theme.warning)
                    }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
private fun EditorLink(title: String, symbol: String, done: Boolean, destination: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    FormRow(onClick = { navigator?.push(destination) }) {
        Sym(symbol, size = 20.dp, tint = Theme.accent)
        T(title, Modifier.weight(1f), style = Type.body)
        Sym(if (done) "checkmark.circle.fill" else "circle", size = 20.dp, tint = if (done) Theme.positive else Theme.secondary)
        Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
    }
}

@Composable
fun StudioBasicsEditor(studio: Studio, onChange: (Studio) -> Unit) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var isUploading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    // Uploads finish one by one; always append to the newest version of the studio.
    var latest by remember { mutableStateOf(studio) }
    latest = studio

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        isUploading = true
        app.scope.launch {
            for (uri in uris) {
                try {
                    val jpeg = withContext(Dispatchers.IO) { ImageCompressor.jpeg(context, uri, 1600) } ?: continue
                    val url = app.backend.uploadImage(jpeg, "studios/${studio.id}")
                    onChange(latest.copy(photoUrls = latest.photoUrls + url))
                } catch (e: Exception) { error = e.userMessage }
            }
            isUploading = false
        }
    }

    NavScreen("Basics & photos") {
        FormSection("Name") {
            FormTextField("Studio name", studio.name, { onChange(studio.copy(name = it)) }, capitalization = KeyboardCapitalization.Words)
            FormTextField("Tagline, e.g. “Warm analog vocals in Exarchia”", studio.tagline, { onChange(studio.copy(tagline = it)) })
        }
        FormSection("Description", footer = L10n.format("%lld characters (min. 40)", studio.description.length), translate = false) {
            FormTextField("Describe the rooms, the vibe, who you work with…", studio.description, { onChange(studio.copy(description = it)) }, minLines = 5, maxLines = 15)
        }
        FormSection("Photos & video", footer = "The first photo is your cover. Show the live room, control room and booth.") {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                studio.photoUrls.forEach { url ->
                    Box(Modifier.size(120.dp, 90.dp).clip(RoundedCornerShape(10.dp))) {
                        RemoteImage(url, Modifier.fillMaxSize())
                        Box(
                            Modifier.align(Alignment.TopEnd).padding(4.dp).size(22.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)
                                .pressable { onChange(studio.copy(photoUrls = studio.photoUrls.filter { it != url })) },
                            contentAlignment = Alignment.Center,
                        ) { Sym("xmark", size = 11.dp, tint = Color.White) }
                    }
                }
                Column(
                    Modifier.size(120.dp, 90.dp).background(Theme.card, RoundedCornerShape(10.dp))
                        .pressable(enabled = !isUploading) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    Sym(if (isUploading) "hourglass" else "plus", tint = Theme.accent)
                    T("Add", style = Type.caption, color = Theme.accent)
                }
            }
            Divider()
            FormTextField("Video link (YouTube, Vimeo…)", studio.videoUrl ?: "", { onChange(studio.copy(videoUrl = it.ifEmpty { null })) },
                keyboard = KeyboardType.Uri, capitalization = KeyboardCapitalization.None)
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun StudioLocationEditor(studio: Studio, onChange: (Studio) -> Unit) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var isLocating by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val address = studio.address

    fun locate() {
        isLocating = true
        app.scope.launch {
            val point = LocationService.geocode(context, studio.address.singleLine)
            if (point != null) {
                onChange(studio.copy(latitude = point.latitude, longitude = point.longitude))
                message = null
            } else {
                message = "We couldn't find that address. Check the spelling."
            }
            isLocating = false
        }
    }

    NavScreen("Address & contact") {
        FormSection("Address", footer = "Artists see the area before booking and the full address after booking.") {
            FormTextField("Street and number", address.street, { onChange(studio.copy(address = address.copy(street = it))) }, capitalization = KeyboardCapitalization.Words)
            FormTextField("Postal code", address.postalCode, { onChange(studio.copy(address = address.copy(postalCode = it))) }, capitalization = KeyboardCapitalization.Characters)
            FormTextField("City", address.city, { onChange(studio.copy(address = address.copy(city = it))) }, capitalization = KeyboardCapitalization.Words)
            FormTextField("Area / neighbourhood", address.area, { onChange(studio.copy(address = address.copy(area = it))) }, capitalization = KeyboardCapitalization.Words)
            FormTextField("Country", address.country, { onChange(studio.copy(address = address.copy(country = it))) }, capitalization = KeyboardCapitalization.Words)
        }
        FormSection {
            FormButton(if (isLocating) "Finding…" else "Find on map", "location.magnifyingglass", enabled = !isLocating && address.city.isNotEmpty()) { locate() }
            if (studio.latitude != 0.0 || studio.longitude != 0.0) {
                key(studio.latitude, studio.longitude) {
                    AndroidView(
                        modifier = Modifier.fillMaxWidth().height(180.dp),
                        factory = {
                            Configuration.getInstance().userAgentValue = context.packageName
                            MapView(it).apply {
                                setTileSource(TileSourceFactory.MAPNIK)
                                setMultiTouchControls(false)
                                zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                                setOnTouchListener { _, _ -> true }
                                val point = org.osmdroid.util.GeoPoint(studio.latitude, studio.longitude)
                                controller.setZoom(16.0)
                                controller.setCenter(point)
                                overlays.add(Marker(this).apply { position = point; title = studio.name.ifEmpty { tr("Studio") } })
                            }
                        },
                    )
                }
            }
            message?.let { FormRow { T(it, style = Type.footnote, color = Theme.secondary) } }
        }
        FormSection("Contact") {
            val contact = studio.contact
            FormTextField("Phone", contact.phone, { onChange(studio.copy(contact = contact.copy(phone = it))) }, keyboard = KeyboardType.Phone)
            FormTextField("Email", contact.email, { onChange(studio.copy(contact = contact.copy(email = it))) }, keyboard = KeyboardType.Email, capitalization = KeyboardCapitalization.None)
            FormTextField("Website", contact.website, { onChange(studio.copy(contact = contact.copy(website = it))) }, keyboard = KeyboardType.Uri, capitalization = KeyboardCapitalization.None)
        }
    }
}

/** Prices & services sections (placed inside a NavScreen by the caller). */
@Composable
fun StudioPricingEditor(studio: Studio, onChange: (Studio) -> Unit) {
    FormSection {
        FormPicker("Currency", studio.currency, listOf("EUR", "DKK", "SEK", "NOK", "GBP", "USD"), { it }, translateOptions = false) { onChange(studio.copy(currency = it)) }
    }
    FormSection("Session types", footer = "e.g. Recording, Recording + engineer, Mixing session, Podcast, Rehearsal.") {
        studio.sessionTypes.forEachIndexed { index, type ->
            fun update(t: SessionType) = onChange(studio.copy(sessionTypes = studio.sessionTypes.toMutableList().also { it[index] = t }))
            key(type.id) {
                SwipeToDelete({ onChange(studio.copy(sessionTypes = studio.sessionTypes.filter { it.id != type.id })) }) {
                    Column(Modifier.background(Theme.card.copy(alpha = 0.01f))) {
                        FormRow { PlainTextField(type.name, { update(type.copy(name = it)) }, "Session name", Modifier.weight(1f), style = Type.headline) }
                        FormRow { PlainTextField(type.details, { update(type.copy(details = it)) }, "Short description", Modifier.weight(1f)) }
                        MoneyField("Per hour", type.hourlyRate, studio.currency) { update(type.copy(hourlyRate = it)) }
                        FormStepper(L10n.format("Minimum %lld h", type.minimumHours), type.minimumHours, 1..8, translate = false) { update(type.copy(minimumHours = it)) }
                        FormToggle("Engineer included", type.includesEngineer) { update(type.copy(includesEngineer = it)) }
                    }
                }
            }
        }
        FormButton("Add session type", "plus") {
            onChange(studio.copy(sessionTypes = studio.sessionTypes + SessionType(newId(), "", "", if (studio.priceFrom > 0) studio.priceFrom else 3000, 1, false)))
        }
    }
    FormSection("Mix, mastering, engineer & producer") {
        studio.addOns.forEachIndexed { index, addOn ->
            fun update(a: ServiceAddOn) = onChange(studio.copy(addOns = studio.addOns.toMutableList().also { it[index] = a }))
            key(addOn.id) {
                SwipeToDelete({ onChange(studio.copy(addOns = studio.addOns.filter { it.id != addOn.id })) }) {
                    Column(Modifier.background(Theme.card.copy(alpha = 0.01f))) {
                        FormPicker("Type", addOn.kind, AddOnKind.entries, { it.title }) { update(addOn.copy(kind = it)) }
                        FormRow { PlainTextField(addOn.name, { update(addOn.copy(name = it)) }, "Name", Modifier.weight(1f)) }
                        MoneyField("Price", addOn.price, studio.currency) { update(addOn.copy(price = it)) }
                        Box(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                            GlassSegmentedControl(addOn.unit, PriceUnit.entries, { tr(it.suffix) }) { update(addOn.copy(unit = it)) }
                        }
                        Divider()
                    }
                }
            }
        }
        FormButton("Add service", "plus") {
            onChange(studio.copy(addOns = studio.addOns + ServiceAddOn(newId(), AddOnKind.Mixing, "Mixing", 5000, PriceUnit.PerTrack)))
        }
    }
}

@Composable
fun MoneyField(title: String, amount: Int, currency: String, onChange: (Int) -> Unit) {
    var text by remember { mutableStateOf(Money.editableString(amount)) }
    FormRow {
        T(title, Modifier.weight(1f), style = Type.body)
        PlainTextField(text, { value -> text = value; Money.parse(value)?.let(onChange) }, "0", Modifier.width(90.dp),
            keyboard = KeyboardType.Decimal, style = Type.body.copy(textAlign = TextAlign.End))
        Txt(currency, style = Type.body, color = Theme.secondary)
    }
}

/** Opening hours sections (placed inside a NavScreen by the caller). */
@Composable
fun OpeningHoursEditor(hours: List<OpeningHours>, onChange: (List<OpeningHours>) -> Unit) {
    LaunchedEffect(Unit) {
        val missing = (1..7).filter { day -> hours.none { it.weekday == day } }
        if (missing.isNotEmpty()) onChange(hours + missing.map { OpeningHours(it, true, 600, 1320) })
    }
    fun update(day: OpeningHours) = onChange(hours.map { if (it.weekday == day.weekday) day else it })

    OpeningHours.displayOrder.forEach { weekday ->
        val day = hours.firstOrNull { it.weekday == weekday } ?: return@forEach
        FormSection(day.weekdayName, translate = false) {
            FormToggle("Open", !day.isClosed) { update(day.copy(isClosed = !it)) }
            if (!day.isClosed) {
                MinutePicker("Opens", day.opensAt, 0..(23 * 60 + 30)) { update(day.copy(opensAt = it)) }
                MinutePicker("Closes", day.closesAt, 60..(30 * 60)) { update(day.copy(closesAt = it)) }
            }
        }
    }
    FormSection(footer = "Closing times after midnight (e.g. 02:00) are allowed for late sessions.") {
        FormButton("Copy Monday to all days") {
            val monday = hours.firstOrNull { it.weekday == 2 } ?: return@FormButton
            onChange(hours.map { it.copy(isClosed = monday.isClosed, opensAt = monday.opensAt, closesAt = monday.closesAt) })
        }
    }
}

@Composable
fun MinutePicker(title: String, minutes: Int, range: IntRange, onChange: (Int) -> Unit) {
    val options = (range.first..range.last step 30).toList()
    FormPicker(title, minutes, options, { OpeningHours.format(it) + if (it >= 24 * 60) " (+1)" else "" }, translateOptions = false, onSelect = onChange)
}

@Composable
fun StudioFeaturesEditor(studio: Studio, onChange: (Studio) -> Unit) {
    var newCategory by remember { mutableStateOf(EquipmentCategory.Microphone) }
    var newItem by remember { mutableStateOf("") }

    NavScreen("Facilities & gear") {
        FormSection("Capacity") {
            FormStepper(L10n.format("Up to %lld people", studio.capacity), studio.capacity, 1..60, translate = false) { onChange(studio.copy(capacity = it)) }
        }
        FormSection("Facilities") {
            Box(Modifier.padding(12.dp)) {
                ChipPicker(Facility.entries, studio.facilities.toSet(), { it.title }, { it.symbol }) { value -> onChange(studio.copy(facilities = Facility.entries.filter { it in value })) }
            }
        }
        FormSection("Genres you work with") {
            Box(Modifier.padding(12.dp)) {
                ChipPicker(Genre.entries, studio.genres.toSet(), { it.title }) { value -> onChange(studio.copy(genres = Genre.entries.filter { it in value })) }
            }
        }
        FormSection("Equipment & microphones") {
            EquipmentCategory.entries.forEach { category ->
                val items = studio.equipment.filter { it.category == category }
                if (items.isNotEmpty()) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        T(category.title, style = Type.caption.bold, color = Theme.secondary)
                        items.forEach { item ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Txt(item.name, Modifier.weight(1f), style = Type.body)
                                Sym("minus.circle.fill", Modifier.pressable { onChange(studio.copy(equipment = studio.equipment.filter { it.id != item.id })) }, size = 20.dp, tint = Theme.red)
                            }
                        }
                    }
                    Divider()
                }
            }
            FormPicker("Category", newCategory, EquipmentCategory.entries, { it.title }) { newCategory = it }
            FormRow {
                PlainTextField(newItem, { newItem = it }, "e.g. Neumann U87 Ai", Modifier.weight(1f))
                LinkButton("Add", enabled = newItem.isNotBlank()) {
                    onChange(studio.copy(equipment = studio.equipment + EquipmentItem(newId(), newCategory, newItem.trim())))
                    newItem = ""
                }
            }
        }
        FormSection("Engineers & producers") {
            studio.engineers.forEachIndexed { index, person ->
                fun update(p: StudioPerson) = onChange(studio.copy(engineers = studio.engineers.toMutableList().also { it[index] = p }))
                key(person.id) {
                    SwipeToDelete({ onChange(studio.copy(engineers = studio.engineers.filter { it.id != person.id })) }) {
                        Column(Modifier.background(Theme.card.copy(alpha = 0.01f))) {
                            FormRow { PlainTextField(person.name, { update(person.copy(name = it)) }, "Name", Modifier.weight(1f), style = Type.headline, capitalization = KeyboardCapitalization.Words) }
                            FormRow { PlainTextField(person.role, { update(person.copy(role = it)) }, "Role (Engineer, Producer…)", Modifier.weight(1f)) }
                            FormRow { PlainTextField(person.bio, { update(person.copy(bio = it)) }, "Short bio", Modifier.weight(1f)) }
                        }
                    }
                }
            }
            FormButton("Add person", "person.badge.plus") {
                onChange(studio.copy(engineers = studio.engineers + StudioPerson(newId(), "", "Engineer", "")))
            }
        }
    }
}

/** Booking settings sections (placed inside a NavScreen by the caller). */
@Composable
fun StudioPolicyEditor(studio: Studio, onChange: (Studio) -> Unit) {
    var newRule by remember { mutableStateOf("") }
    val policy = studio.bookingPolicy
    fun update(p: com.easysesh.app.model.BookingPolicy) = onChange(studio.copy(bookingPolicy = p))

    FormSection("How artists book", footer = if (policy.instantBook) "Artists are confirmed immediately when they book." else
        "You accept or decline each request within 24 hours; unanswered requests expire. Card payments are only charged when you accept.") {
        FormInlinePicker(policy.instantBook, listOf(true, false), { if (it) "Instant booking" else "Request – I approve within 24 hours" }, { if (it) "bolt.fill" else "hourglass" }) {
            update(policy.copy(instantBook = it))
        }
    }
    FormSection("House rules") {
        studio.rules.forEachIndexed { index, rule ->
            key(index, rule) {
                SwipeToDelete({ onChange(studio.copy(rules = studio.rules.filterIndexed { i, _ -> i != index })) }) {
                    FormRow(Modifier.background(Theme.card.copy(alpha = 0.01f))) { Txt(rule, style = Type.body) }
                }
            }
        }
        FormRow {
            PlainTextField(newRule, { newRule = it }, "Add a rule", Modifier.weight(1f))
            LinkButton("Add", enabled = newRule.isNotBlank()) {
                onChange(studio.copy(rules = studio.rules + newRule.trim()))
                newRule = ""
            }
        }
    }
    FormSection {
        FormPicker("Cancellation policy", policy.cancellationPolicy, CancellationPolicy.entries, { it.title }) { update(policy.copy(cancellationPolicy = it)) }
        FormRow { T(policy.cancellationPolicy.summary, style = Type.footnote, color = Theme.secondary) }
    }
    FormSection(footer = "With a deposit, the rest is charged automatically after the session.") {
        FormPicker("Deposit", policy.depositPercent, listOf(0, 20, 30, 50), { if (it == 0) tr("No deposit – full payment") else L10n.format("%lld%% deposit", it) }, translateOptions = false) {
            update(policy.copy(depositPercent = it, acceptsCash = if (it > 0) false else policy.acceptsCash))
        }
    }
    FormSection(
        footer = if (policy.depositPercent > 0) tr("Cash isn't available when you require a deposit.")
        else L10n.format("Artists can choose to pay you in cash at the session. EasySesh's %lld%% platform fee on cash bookings is deducted from your next payout or invoiced monthly. Cash bookings have no card guarantee for no-shows.", studio.feePercent),
        translate = false,
    ) {
        FormToggle("Accept cash payments", policy.acceptsCash, enabled = policy.depositPercent == 0) { update(policy.copy(acceptsCash = it)) }
    }
    FormSection(
        "Check-in",
        footer = if (policy.checkInEnabled) "Recommended. Artists can check in in the app when they arrive and you can confirm it. It protects both of you against fraud and helps EasySesh settle disputes."
        else "Check-in is off. EasySesh can't promise artists a refund if something goes wrong, and artists see this before they book. Disputes are decided on the other evidence available.",
        footerColor = if (policy.checkInEnabled) null else Theme.warning,
    ) {
        FormToggle("Check-in on arrival", policy.checkInEnabled, "location.circle.fill") { update(policy.copy(checkInEnabled = it)) }
    }
    FormSection("Scheduling") {
        FormStepper(L10n.format("Min. notice: %lld h", policy.minimumNoticeHours), policy.minimumNoticeHours, 0..72, translate = false) { update(policy.copy(minimumNoticeHours = it)) }
        SteppedRow(L10n.format("Book up to %lld days ahead", policy.maxAdvanceDays), policy.maxAdvanceDays, 7..365, 7) { update(policy.copy(maxAdvanceDays = it)) }
        SteppedRow(L10n.format("Buffer between sessions: %lld min", policy.bufferMinutes), policy.bufferMinutes, 0..120, 15) { update(policy.copy(bufferMinutes = it)) }
    }
    FormSection("Booking terms") {
        FormTextField("Overtime, damage, guests, recording rights…", policy.terms, { update(policy.copy(terms = it)) }, minLines = 3, maxLines = 10)
    }
}

/** Stepper row with a step size other than 1 (iOS Stepper(step:)). */
@Composable
private fun SteppedRow(title: String, value: Int, range: IntRange, step: Int, onChange: (Int) -> Unit) {
    FormRow {
        Txt(title, Modifier.weight(1f), style = Type.body)
        Stepper(value / step, (range.first / step)..(range.last / step)) { onChange((it * step).coerceIn(range)) }
    }
}

@Composable
fun PayoutAccountEditor(studioId: String, prepare: (suspend () -> Unit)? = null) {
    val app = LocalAppState.current
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var account by remember { mutableStateOf<PayoutAccount?>(null) }
    var holder by remember { mutableStateOf("") }
    var iban by remember { mutableStateOf("") }
    var editingBank by remember { mutableStateOf(false) }
    var isSavingBank by remember { mutableStateOf(false) }
    var isOpeningStripe by remember { mutableStateOf(false) }
    var awaitingStripe by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val current = account
    val hasBank = !current?.ibanLast4.isNullOrEmpty()
    val ibanIsValid = StripeBankTokenizer.isValidIban(iban)

    suspend fun load() {
        account = runCatching { app.backend.payoutAccount(studioId) }.getOrNull()
        if (holder.isEmpty()) holder = account?.accountHolder ?: ""
        if (account?.stripeAccountId != null) runCatching { app.backend.syncPayoutAccount(studioId) }.getOrNull()?.let { account = it }
    }
    LaunchedEffect(Unit) { load() }

    // Stripe's pages open in a browser tab; when the studio comes back, pick up whatever they finished.
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && awaitingStripe) {
                awaitingStripe = false
                app.scope.launch {
                    try { account = app.backend.syncPayoutAccount(studioId) } catch (e: Exception) { error = e.userMessage }
                    isOpeningStripe = false
                }
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    fun saveBank() {
        isSavingBank = true
        app.scope.launch {
            try {
                prepare?.invoke()
                val name = holder.trim()
                val token = StripeBankTokenizer.token(iban, name)
                account = app.backend.savePayoutBank(studioId, name, token)
                iban = ""
                editingBank = false
            } catch (e: Exception) { error = e.userMessage }
            isSavingBank = false
        }
    }

    fun openStripe() {
        isOpeningStripe = true
        app.scope.launch {
            try {
                prepare?.invoke()
                val url = app.backend.payoutOnboardingUrl(studioId)
                if (url == null) { isOpeningStripe = false; return@launch }
                awaitingStripe = true
                CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, Uri.parse(url))
            } catch (e: Exception) {
                error = e.userMessage
                isOpeningStripe = false
            }
        }
    }

    NavScreen("Payout details") {
        FormSection(footerContent = {
            Txt(L10n.format("You're paid only after a session is completed: payouts are sent %lld days after each completed session, minus EasySesh's %lld%% platform fee. Platform fees for cash bookings are deducted from the same payouts.",
                PlatformConfig.PAYOUT_DELAY_DAYS, app.ownedStudio?.feePercent ?: PlatformConfig.PLATFORM_FEE_PERCENT), style = Type.footnote, color = Theme.secondary)
        }) {
            FormRow {
                when {
                    current != null && current.payoutsEnabled -> {
                        Sym("checkmark.seal.fill", size = 20.dp, tint = Theme.positive)
                        Txt(if (current.ibanLast4.isEmpty()) tr("Payouts enabled") else L10n.format("Payouts enabled to •••• %@", current.ibanLast4), Modifier.weight(1f), style = Type.body, color = Theme.positive)
                    }
                    hasBank -> {
                        Sym("person.badge.shield.checkmark", size = 20.dp, tint = Theme.warning)
                        T("Bank added – confirm your identity to receive payouts", Modifier.weight(1f), style = Type.body, color = Theme.warning)
                    }
                    else -> {
                        Sym("exclamationmark.triangle", size = 20.dp, tint = Theme.warning)
                        T("Payouts not set up yet", Modifier.weight(1f), style = Type.body, color = Theme.warning)
                    }
                }
            }
        }

        FormSection("Bank account", footer = "Your bank details go straight to Stripe, our payment provider. EasySesh only keeps the last 4 digits.") {
            if (hasBank && !editingBank && current != null) {
                FormRow {
                    Sym("building.columns.fill", size = 20.dp, tint = Theme.accent)
                    Txt(L10n.format("Bank account •••• %@", current.ibanLast4), Modifier.weight(1f), style = Type.body)
                    LinkButton("Change") { editingBank = true }
                }
                if (current.accountHolder.isNotEmpty()) FormRow { Txt(current.accountHolder, style = Type.footnote, color = Theme.secondary) }
            } else {
                FormTextField("Account holder / company name", holder, { holder = it }, capitalization = KeyboardCapitalization.Words)
                FormTextField("IBAN, e.g. DK50 0040 0440 1162 43", iban, { iban = it }, keyboard = KeyboardType.Ascii,
                    capitalization = KeyboardCapitalization.Characters, style = Type.body.copy(fontFamily = FontFamily.Monospace))
                if (iban.isNotEmpty() && !ibanIsValid) FormRow { T("Check the IBAN – it doesn't look right yet.", style = Type.footnote, color = Theme.warning) }
                FormButton(if (isSavingBank) "Saving…" else "Save bank account", "lock.fill", enabled = !isSavingBank && holder.isNotBlank() && ibanIsValid) { saveBank() }
                if (hasBank) FormButton("Cancel", color = Theme.secondary) { editingBank = false; iban = "" }
            }
        }

        FormSection("Identity check", footer = "Required by law once: Stripe confirms who you are (name, date of birth, address and sometimes a photo ID). It opens right here in the app.") {
            if (current?.payoutsEnabled == true) {
                FormRow {
                    Sym("checkmark.shield.fill", size = 20.dp, tint = Theme.positive)
                    T("Identity confirmed", Modifier.weight(1f), style = Type.body, color = Theme.positive)
                }
            } else {
                FormButton(if (isOpeningStripe) "Opening…" else "Confirm identity", "person.text.rectangle", enabled = !isOpeningStripe && hasBank) { openStripe() }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
