package com.easysesh.app.ui.features

import android.annotation.SuppressLint
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.easysesh.app.core.Distance
import com.easysesh.app.core.GeoPoint
import com.easysesh.app.core.L10n
import com.easysesh.app.core.Money
import com.easysesh.app.core.PlatformConfig
import com.easysesh.app.core.SearchEngine
import com.easysesh.app.core.SearchFilters
import com.easysesh.app.core.StudioResult
import com.easysesh.app.core.StudioSort
import com.easysesh.app.core.AreaSummary
import com.easysesh.app.core.ArtistFilters
import com.easysesh.app.core.ArtistSearch
import com.easysesh.app.core.ArtistSort
import com.easysesh.app.core.addingDays
import com.easysesh.app.core.startOfDay
import com.easysesh.app.core.tr
import com.easysesh.app.data.Backend
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.DiscoveredArtist
import com.easysesh.app.model.EquipmentCategory
import com.easysesh.app.model.Facility
import com.easysesh.app.model.Genre
import com.easysesh.app.model.Interval
import com.easysesh.app.model.Studio
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.CancellationException
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.time.Instant
import java.time.ZoneId

class DiscoverModel {
    var studios by mutableStateOf<List<Studio>>(emptyList())
    var busy by mutableStateOf<Map<String, List<Interval>>>(emptyMap())
    var filters by mutableStateOf(SearchFilters())
    var sort by mutableStateOf(StudioSort.Nearest)
    var isLoading by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    private val engine = SearchEngine()

    suspend fun load(backend: Backend) {
        isLoading = studios.isEmpty()
        try {
            studios = backend.publishedStudios()
            error = null
            loadAvailability(backend)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.userMessage
        } finally {
            isLoading = false
        }
    }

    /** Availability filtering needs bookings/blocks for the chosen day. */
    suspend fun loadAvailability(backend: Backend) {
        val day = filters.availableOn ?: run { busy = emptyMap(); return }
        busy = runCatching { backend.busyIntervals(studios.map { it.id }, day.startOfDay, day.startOfDay.addingDays(2)) }.getOrDefault(emptyMap())
    }

    fun results(origin: GeoPoint?) = engine.search(studios, filters, sort, origin, busy)

    fun summary(origin: GeoPoint, areaName: String, radiusKm: Double): AreaSummary =
        engine.areaSummary(engine.search(studios, SearchFilters(), StudioSort.Nearest, origin), areaName, radiusKm)
}

@Composable
fun DiscoverView() {
    val app = LocalAppState.current
    val model = remember { DiscoverModel() }
    var showMap by remember { mutableStateOf(false) }
    var showFilters by remember { mutableStateOf(false) }
    val origin = app.location.effectiveLocation
    val results = model.results(origin)
    val metric = app.account?.settings?.useMetricUnits ?: true

    LaunchedEffect(Unit) {
        app.location.requestPermission()
        model.load(app.backend)
    }
    LaunchedEffect(model.filters.availableOn, model.filters.sessionHours) { model.loadAvailability(app.backend) }

    NavigationStack {
        val navigator = LocalNavigator.current
        if (showMap) {
            Box(Modifier.fillMaxSize()) {
                StudioMapView(results, metric) { result -> navigator?.push { StudioDetailView(result.studio.id, result.studio) } }
                Column(Modifier.statusBarsPadding().padding(horizontal = 16.dp).padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) { SearchField(model) }
                        GlassIconButton("list.bullet", "Show list") { showMap = false }
                    }
                    ControlsRow(model, results.size) { showFilters = true }
                }
            }
        } else {
            EasySeshScreen(
                "Find a studio",
                eyebrow = app.location.cityName ?: greeting(),
                refresh = { model.load(app.backend) },
                trailing = { GlassIconButton("map", "Show map") { showMap = true } },
            ) {
                SearchField(model)
                ControlsRow(model, results.size) { showFilters = true }
                AreaSummaryCard(
                    model.summary(origin, app.location.cityName ?: tr("Your area"), app.account?.settings?.searchRadiusKm ?: 5.0),
                    results.size, model.filters.query.isNotEmpty(),
                )
                when {
                    model.isLoading -> ProgressSpinner()
                    results.isEmpty() -> {
                        GlassEmptyState("No studios found", "waveform.slash", "Try widening your filters or search area.")
                        if (model.filters.activeCount > 0) SecondaryButton("Clear filters") { model.filters = SearchFilters() }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    results.forEach { result ->
                        StudioCard(result, metric, Modifier.pressable { navigator?.push { StudioDetailView(result.studio.id, result.studio) } })
                    }
                }
            }
        }
    }
    if (showFilters) {
        Sheet(onDismiss = { showFilters = false }) { FilterSheet(model.filters) { model.filters = it } }
    }
    ErrorAlert(model.error) { model.error = null }
}

@Composable
private fun SearchField(model: DiscoverModel) {
    var focused by remember { mutableStateOf(false) }
    GlassField("magnifyingglass", focused) {
        PlainTextField(model.filters.query, { model.filters = model.filters.copy(query = it) }, "Studio, area or city",
            Modifier.weight(1f).onFocusChanged { focused = it.isFocused })
        if (model.filters.query.isNotEmpty()) {
            Box(Modifier.clickable { model.filters = model.filters.copy(query = "") }) { Sym("xmark.circle.fill", tint = Theme.secondary) }
        }
    }
}

@Composable
private fun ControlsRow(model: DiscoverModel, count: Int, onFilters: () -> Unit) {
    var sortOpen by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        FilterPill(
            if (model.filters.activeCount > 0) L10n.format("Filters · %lld", model.filters.activeCount) else tr("Filters"),
            "slider.horizontal.3", model.filters.activeCount > 0, Modifier.pressable(onClick = onFilters),
        )
        Box {
            FilterPill(tr(model.sort.title), "arrow.up.arrow.down", false, Modifier.pressable { sortOpen = true })
            DropdownMenu(sortOpen, { sortOpen = false }, containerColor = Theme.card) {
                StudioSort.entries.forEach { sort ->
                    DropdownMenuItem(
                        text = { T(sort.title) },
                        trailingIcon = if (sort == model.sort) ({ Sym("checkmark", tint = Theme.accent) }) else null,
                        onClick = { model.sort = sort; sortOpen = false },
                    )
                }
            }
        }
        Fill()
        Row(
            Modifier.background(Theme.card.copy(alpha = 0.78f), CircleShape).border(0.8.dp, Theme.colors.glassEdge, CircleShape).padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Box(Modifier.size(7.dp).neonGlow(Theme.magenta, 4.dp, CircleShape).background(Theme.neon, CircleShape))
            Txt(L10n.format("%lld studios", count), style = Type.footnote.bold)
        }
    }
}

/** Pill used for Filters / Sort: glass when idle, neon when a filter is active. */
@Composable
fun FilterPill(title: String, symbol: String, isActive: Boolean, modifier: Modifier = Modifier) {
    Row(
        modifier
            .then(if (isActive) Modifier.neonGlow(Theme.magenta, 8.dp, CircleShape) else Modifier)
            .background(if (isActive) Theme.neon else Brush.linearGradient(listOf(Theme.card.copy(alpha = 0.78f), Theme.card.copy(alpha = 0.78f))), CircleShape)
            .border(0.8.dp, if (isActive) Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)) else Theme.colors.glassEdge, CircleShape)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Sym(symbol, size = 15.dp, tint = if (isActive) Color.White else Theme.magenta)
        Txt(title, style = Type.subheadline.semibold, color = if (isActive) Color.White else Theme.primary, maxLines = 1)
    }
}

@Composable
fun AreaSummaryCard(summary: AreaSummary, totalCount: Int = 0, isSearching: Boolean = false) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Eyebrow(if (isSearching) "Results" else "Near you")
        Txt(if (isSearching) L10n.format("%lld studios", totalCount) else summary.areaName, style = Type.display(30).tracking(-0.5f))
        val radius = summary.radiusKm.toInt()
        val text = when {
            isSearching -> tr("Searching everywhere, sorted by distance.")
            summary.studioCount == 0 && totalCount > 0 ->
                L10n.format("No studios within %lld km yet – %lld elsewhere. Search a city or country to find them.", radius, totalCount)
            else -> L10n.format("%lld studios within %lld km", summary.studioCount, radius) +
                (summary.priceFrom?.let { " · " + L10n.format("from %@/h", Money.format(it, summary.currency)) } ?: "")
        }
        Txt(text, style = Type.subheadline, color = Theme.secondary)
    }
}

/** Photo-first listing card: image on top, facts underneath, no chrome. */
@Composable
fun StudioCard(result: StudioResult, metric: Boolean = true, modifier: Modifier = Modifier) {
    val studio = result.studio
    val shape = RoundedCornerShape(Theme.corner)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(shape)
            .border(if (studio.isPromoted) 1.5.dp else 0.8.dp, if (studio.isPromoted) Theme.neon else Theme.colors.glassEdge, shape)) {
            RemoteImage(studio.photoUrls.firstOrNull(), Modifier.fillMaxSize())
            if (studio.bookingPolicy.instantBook) {
                Row(
                    Modifier.align(Alignment.TopStart).padding(10.dp).background(Theme.card.copy(alpha = 0.8f), CircleShape)
                        .border(0.8.dp, Theme.colors.glassEdge, CircleShape).padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Sym("bolt.fill", size = 13.dp, tint = Theme.magenta)
                    T("Instant book", style = Type.caption.semibold)
                }
            }
            if (studio.isPromoted) Box(Modifier.align(Alignment.TopEnd).padding(10.dp)) { PromotedTag() }
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Txt(studio.name, Modifier.weight(1f, fill = false), style = Type.headline, maxLines = 1)
                if (studio.isVerified) VerifiedBadge()
                if (studio.showsAdminBadge) AdminBadge(compact = true)
                Fill()
                RatingLabel(studio.ratingAverage, studio.reviewCount, compact = true)
            }
            val parts = listOfNotNull(studio.address.publicArea, result.distance?.let { Distance.format(it, metric) })
            Txt(parts.joinToString(" · "), style = Type.subheadline, color = Theme.secondary, maxLines = 1)
            Row(Modifier.padding(top = 2.dp)) {
                Txt(Money.format(studio.priceFrom, studio.currency), style = Type.subheadline.semibold)
                Txt(" " + tr("/ hour"), style = Type.subheadline, color = Theme.secondary)
            }
            if (studio.specialTags.isNotEmpty()) {
                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { studio.specialTags.take(2).forEach { SpecialTagChip(it) } }
            }
        }
    }
}

/** Map of the results (OpenStreetMap, no API key needed). Tap a price marker to see the studio. */
@SuppressLint("ClickableViewAccessibility")
@Composable
fun StudioMapView(results: List<StudioResult>, metric: Boolean, onOpen: (StudioResult) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var selectedId by remember { mutableStateOf<String?>(null) }
    var fitRequest by remember { mutableStateOf(0) }
    val accent = Theme.accent
    Box(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = {
                Configuration.getInstance().userAgentValue = context.packageName
                MapView(it).apply {
                    setTileSource(TileSourceFactory.MAPNIK)
                    setMultiTouchControls(true)
                    zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                }
            },
            update = { map ->
                map.overlays.clear()
                results.forEach { result ->
                    val marker = Marker(map)
                    marker.position = org.osmdroid.util.GeoPoint(result.studio.latitude, result.studio.longitude)
                    marker.title = result.studio.name
                    marker.snippet = Money.format(result.studio.priceFrom, result.studio.currency)
                    marker.setOnMarkerClickListener { _, _ -> selectedId = result.id; true }
                    map.overlays.add(marker)
                }
                fitAll(map, results)
                map.invalidate()
            },
        )
        if (results.isNotEmpty()) {
            Row(
                Modifier.align(Alignment.TopCenter).padding(top = 150.dp).background(Theme.card, CircleShape).border(0.8.dp, Theme.colors.glassEdge, CircleShape)
                    .pressable { fitRequest++ ; selectedId = null }.padding(horizontal = 14.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Sym("scope", size = 16.dp, tint = accent)
                Txt(L10n.format("All studios · %lld", results.size), style = Type.subheadline.bold)
            }
        }
        results.firstOrNull { it.id == selectedId }?.let { selected ->
            Box(Modifier.align(Alignment.BottomCenter).padding(16.dp)) {
                GlassCard(padding = 10.dp, onClick = { onOpen(selected) }) { StudioCard(selected, metric) }
            }
        }
    }
}

private fun fitAll(map: MapView, results: List<StudioResult>) {
    if (results.isEmpty()) return
    val lats = results.map { it.studio.latitude }
    val lons = results.map { it.studio.longitude }
    val pad = 0.02
    val box = BoundingBox(lats.max() + pad, lons.max() + pad, lats.min() - pad, lons.min() - pad)
    map.post { runCatching { map.zoomToBoundingBox(box, false, 80) } }
}

@Composable
fun FilterSheet(initial: SearchFilters, onApply: (SearchFilters) -> Unit) {
    val dismiss = LocalDismiss.current
    var draft by remember { mutableStateOf(initial) }
    val priceSteps = listOf<Int?>(null, 1500, 2500, 4000, 6000)
    val distanceSteps = listOf<Double?>(null, 2.0, 5.0, 10.0, 25.0)
    val ratingSteps = listOf<Double?>(null, 4.0, 4.5, 4.8)
    val zone = ZoneId.systemDefault()

    NavScreen(
        "Filters",
        leading = { ToolbarButton("Reset") { draft = SearchFilters(query = initial.query) } },
        actions = { ToolbarButton("Show results", bold = true) { onApply(draft); dismiss() } },
    ) {
        FormSection("Max price per hour") {
            FormContent {
                GlassSegmentedControl(draft.maxPrice, priceSteps, { it?.let { Money.format(it, "EUR") } ?: "Any" }) { draft = draft.copy(maxPrice = it) }
            }
        }
        FormSection("Distance") {
            FormContent {
                GlassSegmentedControl(draft.maxDistanceKm, distanceSteps, { it?.let { L10n.format("%lld km", it.toInt()) } ?: "Any" }) { draft = draft.copy(maxDistanceKm = it) }
            }
        }
        FormSection("Availability") {
            FormToggle("Available on a specific day", draft.availableOn != null) {
                draft = draft.copy(availableOn = if (it) Instant.now().addingDays(1).startOfDay else null)
            }
            draft.availableOn?.let { day ->
                FormDateRow("Day", day.atZone(zone).toLocalDate(), min = java.time.LocalDate.now()) {
                    draft = draft.copy(availableOn = it.atStartOfDay(zone).toInstant())
                }
                FormStepper(L10n.format("For at least %lld hours", draft.sessionHours), draft.sessionHours, 1..PlatformConfig.MAX_SESSION_HOURS, translate = false) {
                    draft = draft.copy(sessionHours = it)
                }
            }
            FormToggle("Instant book only", draft.instantBookOnly) { draft = draft.copy(instantBookOnly = it) }
        }
        FormSection("Rating") {
            FormContent {
                GlassSegmentedControl(draft.minRating, ratingSteps, { it?.let { r -> "%.1f+".format(r) } ?: "Any" }) { draft = draft.copy(minRating = it) }
            }
        }
        FormSection("Genres") {
            FormContent { ChipPicker(Genre.entries, draft.genres, { it.title }) { draft = draft.copy(genres = it) } }
        }
        FormSection("Facilities") {
            FormContent { ChipPicker(Facility.entries, draft.facilities, { it.title }, { it.symbol }) { draft = draft.copy(facilities = it) } }
        }
        FormSection("Services") {
            FormToggle("Engineer available", draft.engineerIncluded) { draft = draft.copy(engineerIncluded = it) }
            FormToggle("Mixing", draft.offersMixing) { draft = draft.copy(offersMixing = it) }
            FormToggle("Mastering", draft.offersMastering) { draft = draft.copy(offersMastering = it) }
        }
        FormSection("Equipment") {
            FormTextField("e.g. U87, SM7B, Neve", draft.equipmentQuery, { draft = draft.copy(equipmentQuery = it) })
            FormContent { ChipPicker(EquipmentCategory.entries, draft.equipmentCategories, { it.title }) { draft = draft.copy(equipmentCategories = it) } }
        }
    }
}

// MARK: Find artists (studios)

/**
 * Studios find artists the way artists find studios: search, filters and sorting over every artist,
 * promoted artists first with a Promoted tag. "Message" writes to them (a message request unless they
 * booked the studio before).
 */
@Composable
fun FindArtistsView() {
    val app = LocalAppState.current
    var artists by remember { mutableStateOf<List<DiscoveredArtist>>(emptyList()) }
    var filters by remember { mutableStateOf(ArtistFilters()) }
    var sort by remember { mutableStateOf(ArtistSort.Recommended) }
    var isLoading by remember { mutableStateOf(true) }
    var showFilters by remember { mutableStateOf(false) }
    var sortOpen by remember { mutableStateOf(false) }
    var messaging by remember { mutableStateOf<DiscoveredArtist?>(null) }
    var focused by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        try { artists = app.backend.discoverArtists() } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.userMessage }
        isLoading = false
    }
    LaunchedEffect(Unit) { load() }
    val results = ArtistSearch.search(artists, filters, sort)

    NavigationStack {
        val navigator = LocalNavigator.current
        EasySeshScreen("Find artists", eyebrow = tr("For your studio"), refresh = { load() }) {
            GlassField("magnifyingglass", focused) {
                PlainTextField(filters.query, { filters = filters.copy(query = it) }, "Artist, genre or city", Modifier.weight(1f).onFocusChanged { focused = it.isFocused })
                if (filters.query.isNotEmpty()) Sym("xmark.circle.fill", Modifier.pressable { filters = filters.copy(query = "") }, tint = Theme.secondary)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                FilterPill(if (filters.activeCount > 0) L10n.format("Filters · %lld", filters.activeCount) else tr("Filters"),
                    "slider.horizontal.3", filters.activeCount > 0, Modifier.pressable { showFilters = true })
                Box {
                    FilterPill(tr(sort.title), "arrow.up.arrow.down", false, Modifier.pressable { sortOpen = true })
                    DropdownMenu(sortOpen, { sortOpen = false }, containerColor = Theme.card) {
                        ArtistSort.entries.forEach { option ->
                            DropdownMenuItem(
                                text = { T(option.title) },
                                trailingIcon = if (option == sort) ({ Sym("checkmark", tint = Theme.accent) }) else null,
                                onClick = { sort = option; sortOpen = false },
                            )
                        }
                    }
                }
                Fill()
                Txt(L10n.format("%lld artists", results.size), style = Type.footnote.bold)
            }
            if (results.any { it.isPromoted }) T("Promoted artists are shown first.", style = Type.caption, color = Theme.secondary)
            when {
                isLoading -> ProgressSpinner()
                results.isEmpty() -> {
                    GlassEmptyState("No artists found", "music.mic", "Try another search or fewer filters.")
                    if (filters.activeCount > 0) SecondaryButton("Clear filters") { filters = ArtistFilters(query = filters.query) }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                results.forEach { artist ->
                    ArtistDiscoveryCard(artist, onOpen = { navigator?.push { ArtistPublicProfileView(artist.id, null) } }, onMessage = { messaging = artist })
                }
            }
        }
    }
    if (showFilters) Sheet({ showFilters = false }) { ArtistFilterSheet(filters) { filters = it } }
    messaging?.let { artist ->
        Sheet({ messaging = null }) {
            NewMessageSheet(artist.searchResult) { conversation -> app.open(com.easysesh.app.services.DeepLink.ConversationLink(conversation.id)) }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
private fun ArtistDiscoveryCard(artist: DiscoveredArtist, onOpen: () -> Unit, onMessage: () -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    GlassCard(if (artist.isPromoted) Modifier.border(1.5.dp, Theme.neon, shape) else Modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.pressable(onClick = onOpen), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                Avatar(artist.avatarUrl, artist.artistName, 58.dp, if (artist.isPromoted) Modifier.border(2.dp, Theme.neon, CircleShape) else Modifier)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(artist.artistName, Modifier.weight(1f, fill = false), style = Type.headline, maxLines = 1)
                        if (artist.isVerified) VerifiedBadge()
                        if (artist.hasAdminBadge) AdminBadge(compact = true)
                    }
                    Txt(listOf(artist.city, if (artist.hasBooked) tr("Booked you before") else "").filter { it.isNotEmpty() }.joinToString(" · "),
                        style = Type.subheadline, color = Theme.secondary, maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (artist.reviewCount > 0) RatingLabel(artist.ratingAverage, artist.reviewCount, compact = true)
                        if (artist.sessionCount > 0) Txt(L10n.format("%lld sessions", artist.sessionCount), style = Type.caption, color = Theme.secondary)
                    }
                }
                if (artist.isPromoted) PromotedTag()
            }
            if (artist.bio.isNotEmpty()) Txt(artist.bio, style = Type.footnote, color = Theme.secondary, maxLines = 2)
            if (artist.genres.isNotEmpty()) {
                Txt(artist.genres.take(4).joinToString(" · ") { g -> Genre.entries.firstOrNull { it.raw == g }?.let { tr(it.title) } ?: g },
                    style = Type.caption.semibold, color = Theme.accent)
            }
            SecondaryButton("Message", Modifier.fillMaxWidth(), symbol = "bubble.left", onClick = onMessage)
        }
    }
}

@Composable
private fun ArtistFilterSheet(initial: ArtistFilters, onApply: (ArtistFilters) -> Unit) {
    val dismiss = LocalDismiss.current
    var draft by remember { mutableStateOf(initial) }
    val ratingSteps = listOf<Double?>(null, 4.0, 4.5, 4.8)
    NavScreen(
        "Filters",
        leading = { ToolbarButton("Reset") { draft = ArtistFilters(query = initial.query) } },
        actions = { ToolbarButton("Show results", bold = true) { onApply(draft); dismiss() } },
    ) {
        FormSection("Rating") {
            FormContent {
                GlassSegmentedControl(draft.minRating, ratingSteps, { it?.let { r -> "%.1f+".format(r) } ?: "Any" }) { draft = draft.copy(minRating = it) }
            }
        }
        FormSection("Artists") {
            FormToggle("Verified artists only", draft.verifiedOnly) { draft = draft.copy(verifiedOnly = it) }
            FormToggle("Booked your studio before", draft.bookedBefore) { draft = draft.copy(bookedBefore = it) }
        }
        FormSection("Genres") {
            FormContent { ChipPicker(Genre.entries, draft.genres, { it.title }) { draft = draft.copy(genres = it) } }
        }
    }
}
