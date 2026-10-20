package com.easysesh.app.ui.features

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.core.Dates
import com.easysesh.app.core.ImageCompressor
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.model.BlockedUser
import com.easysesh.app.model.Booking
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.Genre
import com.easysesh.app.model.SocialLink
import com.easysesh.app.model.SocialPlatform
import com.easysesh.app.model.UserRole
import com.easysesh.app.model.UserSettings
import com.easysesh.app.services.PushNotifications
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ArtistTabView() {
    val app = LocalAppState.current
    EasySeshTabContainer(
        selection = app.selectedTab,
        onSelect = { app.selectTab(it) },
        tabs = listOf(
            TabSpec(AppTab.Discover, "Discover", "sparkle.magnifyingglass"),
            TabSpec(AppTab.Bookings, "Sessions", "calendar"),
            TabSpec(AppTab.Messages, "Messages", "bubble.left.and.bubble.right", app.unreadMessages),
            TabSpec(AppTab.Notifications, "Inbox", "bell", app.unreadNotifications),
            TabSpec(AppTab.Profile, "Profile", "person.crop.circle"),
        ),
        resets = app.tabResetCounter,
    ) { tab ->
        when (tab) {
            AppTab.Bookings -> ArtistBookingsView()
            AppTab.Messages -> ConversationsView()
            AppTab.Notifications -> NotificationsView()
            AppTab.Profile -> ArtistProfileView()
            else -> DiscoverView()
        }
    }
}

/** First-run profile setup after sign-up. */
@Composable
fun ArtistOnboardingView() {
    val app = LocalAppState.current
    val account = app.account ?: return
    NavigationStack { ArtistProfileEditor(app.artistProfile ?: ArtistProfile.empty(account.id), isOnboarding = true) }
}

@Composable
fun ArtistProfileView() {
    val app = LocalAppState.current
    val context = LocalContext.current
    var isEditing by remember { mutableStateOf(false) }
    var bookings by remember { mutableStateOf<List<Booking>>(emptyList()) }
    var pendingStudioLinks by remember { mutableStateOf(0) }
    val navigator = remember { Navigator() }

    suspend fun load() {
        runCatching { app.backend.artistBookings() }.getOrNull()?.let { bookings = it }
        val id = app.account?.id ?: return
        runCatching { app.backend.artistProfile(id) }.getOrNull()?.let { app.artistProfile = it }
        runCatching { app.backend.artistStudioLinks(id) }.getOrNull()?.let { links -> pendingStudioLinks = links.count { !it.isAccepted } }
    }
    LaunchedEffect(Unit) { load() }

    NavigationStack(navigator) {
        EasySeshScreen("Profile", eyebrow = greeting(), refresh = { load() }, trailing = {
            GlassIconButton("pencil", "Edit profile") { isEditing = true }
        }) {
            val profile = app.artistProfile
            if (profile != null) {
                // Hero
                GlassCard(padding = 20.dp, cornerRadius = 26.dp) {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Box {
                            GlowingAvatar(profile.avatarUrl, profile.artistName, 104.dp)
                            Box(
                                Modifier.align(Alignment.BottomEnd).size(32.dp).background(Theme.neon, CircleShape)
                                    .border(2.dp, Color.White.copy(alpha = 0.8f), CircleShape).pressable { isEditing = true },
                                contentAlignment = Alignment.Center,
                            ) { Sym("camera.fill", size = 14.dp, tint = Color.White) }
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(profile.artistName.ifEmpty { tr("Artist") }, style = Type.system(26, FontWeight.ExtraBold).tracking(-0.5f))
                                if (profile.isVerified) VerifiedBadge()
                                if (profile.hasAdminBadge == true) AdminBadge()
                                if (profile.isPromoted) PromotedTag()
                            }
                            if (profile.city.isNotEmpty()) {
                                Row(
                                    Modifier.background(Theme.card.copy(alpha = 0.6f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
                                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Sym("mappin.and.ellipse", size = 13.dp, tint = Theme.secondary)
                                    Txt(profile.city, style = Type.subheadline.semibold, color = Theme.secondary)
                                }
                            }
                        }
                        if (profile.genres.isNotEmpty()) {
                            FlowLayout(6.dp) {
                                profile.genres.forEach { genre ->
                                    T(genre.title, Modifier.background(Theme.violet.copy(alpha = 0.14f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
                                        style = Type.caption.bold, color = Theme.violet)
                                }
                            }
                        }
                        if (profile.bio.isNotEmpty()) Txt(profile.bio, style = Type.subheadline, color = Theme.secondary, align = TextAlign.Center)
                    }
                }

                // Stats
                val completed = bookings.filter { it.status == BookingStatus.Completed }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatCard("Sessions", "${completed.size}", "waveform", TilePalette.signal, Modifier.weight(1f))
                    StatCard("Upcoming", "${bookings.count { it.isUpcoming }}", "calendar", TilePalette.ocean, Modifier.weight(1f))
                    StatCard("Studios", "${completed.map { it.studioId }.toSet().size}", "building.2.fill", TilePalette.violet, Modifier.weight(1f))
                }

                if (profile.links.isNotEmpty()) {
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        profile.links.forEach { link ->
                            val url = link.resolvedUrl ?: return@forEach
                            Row(
                                Modifier.background(Theme.card.copy(alpha = 0.6f), CircleShape).border(0.8.dp, Theme.stroke, CircleShape)
                                    .pressable { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Sym(link.platform.symbol, size = 15.dp)
                                T(link.platform.title, style = Type.subheadline.semibold)
                            }
                        }
                    }
                }

                if (!profile.isVerified) {
                    GlassCard(padding = 14.dp) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                            IconTile("checkmark.seal.fill", 36.dp, listOf(Theme.colors.blue, Theme.cyan))
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                T("Get verified", style = Type.subheadline.bold)
                                T("Verified artists get a badge. Link your Spotify or Instagram and our team will verify you.", style = Type.caption, color = Theme.secondary)
                            }
                        }
                    }
                }

                if (pendingStudioLinks > 0) {
                    GlassCard(padding = 14.dp, onClick = { navigator.push { ArtistPublicProfileView(profile.id, profile) } }) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            IconTile("link", 36.dp, TilePalette.violet)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                T("A studio wants to connect", style = Type.subheadline.bold)
                                T("Confirm to show it on your profile", style = Type.caption, color = Theme.secondary)
                            }
                            PulseDot(Theme.accent, true)
                        }
                    }
                }
            }

            val tiles = buildList<ProfileTile> {
                profile?.let { p -> add(ProfileTile("Public profile", "Studio & ratings", "person.text.rectangle.fill", TilePalette.signal) { ArtistPublicProfileView(p.id, p) }) }
                add(ProfileTile("Sessions", "History & receipts", "clock.arrow.circlepath", TilePalette.ocean) { BookingHistoryView() })
                add(ProfileTile("Account", "Notifications & data", "person.crop.circle.fill", TilePalette.muted) { SettingsView() })
                add(ProfileTile("App settings", "Language, look, storage", "slider.horizontal.3", TilePalette.violet) { AppSettingsView() })
                add(ProfileTile("Support", "Talk to EasySesh", "questionmark.bubble.fill", listOf(Theme.warning, Theme.accent)) { SupportCenterView() })
            }
            ProfileTileGrid(tiles)

            GlassCard(padding = 12.dp, onClick = { navigator.push { LegalListView() } }) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconTile("doc.text.fill", 32.dp, TilePalette.muted)
                    T("Terms & privacy", Modifier.weight(1f), style = Type.body.weight(FontWeight.Medium))
                    Sym("chevron.right", size = 13.dp, tint = Theme.tertiary)
                }
            }
            SignOutButton()
        }
    }

    if (isEditing) {
        app.artistProfile?.let { profile -> Sheet({ isEditing = false }) { ArtistProfileEditor(profile, isOnboarding = false) } }
    }
}

/** A navigation tile on the profile tabs. */
class ProfileTile(val title: String, val subtitle: String, val symbol: String, val colors: List<Color>, val destination: @Composable () -> Unit)

/** Two-column grid of profile tiles (iOS LazyVGrid). */
@Composable
fun ProfileTileGrid(tiles: List<ProfileTile>) {
    val navigator = LocalNavigator.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        tiles.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { tile ->
                    GlassCard(Modifier.weight(1f), padding = 14.dp, cornerRadius = 20.dp, onClick = { navigator?.push(tile.destination) }) {
                        IconTile(tile.symbol, 38.dp, tile.colors)
                        VSpace(14.dp)
                        T(tile.title, style = Type.subheadline.bold)
                        T(tile.subtitle, style = Type.caption, color = Theme.secondary, maxLines = 1)
                    }
                }
                if (row.size == 1) Box(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun StatCard(title: String, value: String, symbol: String, colors: List<Color> = TilePalette.signal, modifier: Modifier = Modifier) {
    GlassCard(modifier, padding = 14.dp, cornerRadius = 20.dp) {
        IconTile(symbol, 30.dp, colors)
        VSpace(12.dp)
        Txt(value, style = Type.system(24, FontWeight.ExtraBold), maxLines = 1)
        T(title, style = Type.caption.weight(FontWeight.Medium), color = Theme.secondary, maxLines = 1)
    }
}

/** Avatar with a neon ring and a soft glow behind it. */
@Composable
fun GlowingAvatar(url: String?, name: String, size: Dp, uploading: Boolean = false) {
    Box(contentAlignment = Alignment.Center) {
        Box(Modifier.size(size + 20.dp).blur(18.dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded).alpha(0.55f).background(Theme.neon, CircleShape))
        Box(Modifier.shadow(10.dp, CircleShape).border(3.dp, Theme.neon, CircleShape).padding(4.dp), contentAlignment = Alignment.Center) {
            Avatar(url, name, size)
            if (uploading) {
                Box(Modifier.size(size).background(Color.Black.copy(alpha = 0.45f), CircleShape), contentAlignment = Alignment.Center) { ProgressSpinner() }
            }
        }
    }
}

@Composable
fun ArtistProfileEditor(initial: ArtistProfile, isOnboarding: Boolean) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val context = LocalContext.current
    var profile by remember { mutableStateOf(initial) }
    var genres by remember { mutableStateOf(initial.genres.toSet()) }
    var isSaving by remember { mutableStateOf(false) }
    var isUploading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var focus by remember { mutableStateOf<String?>(null) }
    val canSave = !isSaving && profile.artistName.isNotBlank() && profile.city.isNotEmpty()

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        isUploading = true
        app.scope.launch {
            try {
                val jpeg = withContext(Dispatchers.IO) { ImageCompressor.jpeg(context, uri, 800) }
                if (jpeg != null) profile = profile.copy(avatarUrl = app.backend.uploadImage(jpeg, "avatars/${profile.id}"))
            } catch (e: Exception) { error = e.userMessage }
            isUploading = false
        }
    }

    fun save() {
        isSaving = true
        val toSave = profile.copy(genres = Genre.entries.filter { it in genres })
        app.scope.launch {
            try {
                app.artistProfile = app.backend.saveArtistProfile(toSave)
                if (!isOnboarding) dismiss()
            } catch (e: Exception) { error = e.userMessage }
            isSaving = false
        }
    }

    fun setLink(platform: SocialPlatform, value: String) {
        val others = profile.links.filter { it.platform != platform }
        val trimmed = value.trim()
        profile = profile.copy(links = if (trimmed.isEmpty()) others else others + SocialLink(platform, trimmed))
    }

    NavScreen(
        if (isOnboarding) "Welcome" else "Edit profile",
        auroraHeight = 420.dp,
        leading = {
            if (isOnboarding) ToolbarButton("Sign out") { app.scope.launch { app.signOut() } }
            else ToolbarButton("Cancel") { dismiss() }
        },
        actions = { ToolbarButton(if (isOnboarding) "Continue" else "Save", enabled = canSave, bold = true) { save() } },
    ) {
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            if (isOnboarding) {
                Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    T("Set up your artist profile", style = Type.system(30, FontWeight.ExtraBold).tracking(-0.6f))
                    T("Studios see this when you book or message them.", style = Type.body, color = Theme.secondary)
                }
            }

            // Avatar picker
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.pressable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                    GlowingAvatar(profile.avatarUrl, profile.artistName.ifEmpty { "?" }, 116.dp, isUploading)
                    Box(
                        Modifier.align(Alignment.BottomEnd).offset((-4).dp, (-4).dp).size(36.dp).background(Theme.neon, CircleShape)
                            .border(2.dp, Color.White.copy(alpha = 0.85f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Sym("camera.fill", size = 15.dp, tint = Color.White) }
                }
                if (profile.artistName.isEmpty()) T("Add a photo", style = Type.headline, color = Theme.secondary)
                else Txt(profile.artistName, style = Type.headline)
            }

            EditorSection("About you") {
                GlassField("person.fill", focus == "name") {
                    PlainTextField(profile.artistName, { profile = profile.copy(artistName = it) }, "Artist name",
                        Modifier.weight(1f).onFocusChanged { if (it.isFocused) focus = "name" }, capitalization = KeyboardCapitalization.Words)
                }
                GlassField("mappin.and.ellipse", focus == "city") {
                    PlainTextField(profile.city, { profile = profile.copy(city = it) }, "City",
                        Modifier.weight(1f).onFocusChanged { if (it.isFocused) focus = "city" }, capitalization = KeyboardCapitalization.Words)
                }
                val bioFocused = focus == "bio"
                val shape = RoundedCornerShape(18.dp)
                Column(
                    Modifier.fillMaxWidth()
                        .then(if (bioFocused) Modifier.neonGlow(Theme.magenta, 10.dp, shape) else Modifier)
                        .background(Theme.card.copy(alpha = 0.7f), shape)
                        .then(if (bioFocused) Modifier.border(1.6.dp, Theme.neon, shape) else Modifier.border(1.dp, Theme.primary.copy(alpha = 0.1f), shape))
                        .padding(16.dp),
                    horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    PlainTextField(profile.bio, { profile = profile.copy(bio = it) }, "Short bio",
                        Modifier.fillMaxWidth().onFocusChanged { if (it.isFocused) focus = "bio" }, minLines = 3, maxLines = 8)
                    Txt("${profile.bio.length}/300", style = Type.caption2.semibold, color = if (profile.bio.length > 300) Theme.warning else Theme.secondary)
                }
            }

            EditorSection("Genres", trailing = if (genres.isEmpty()) null else L10n.format("%lld selected", genres.size)) {
                FlowLayout(8.dp) {
                    Genre.entries.forEach { genre ->
                        val isOn = genre in genres
                        Chip(genre.title, if (isOn) "checkmark" else null, isOn, modifier = Modifier.pressable(haptic = true) {
                            genres = if (isOn) genres - genre else genres + genre
                        })
                    }
                }
            }

            EditorSection("Links", footer = "Paste profile links, e.g. https://open.spotify.com/artist/…") {
                SocialPlatform.entries.forEach { platform ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconTile(platform.symbol, 36.dp, platform.brandColors)
                        Box(Modifier.weight(1f)) {
                            GlassField("link", focus == platform.raw) {
                                PlainTextField(profile.links.firstOrNull { it.platform == platform }?.url ?: "", { setLink(platform, it) }, platform.title,
                                    Modifier.weight(1f).onFocusChanged { if (it.isFocused) focus = platform.raw }, keyboard = KeyboardType.Uri, capitalization = KeyboardCapitalization.None)
                            }
                        }
                    }
                }
            }

            PrimaryButton(if (isOnboarding) "Continue" else "Save", Modifier.fillMaxWidth().padding(top = 4.dp), enabled = canSave) { save() }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
private fun EditorSection(title: String, trailing: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Eyebrow(title, Modifier.weight(1f))
            if (trailing != null) Txt(trailing, style = Type.caption.bold, color = Theme.accent)
        }
        content()
        if (footer != null) T(footer, style = Type.caption, color = Theme.secondary)
    }
}

@Composable
fun SettingsView() {
    val app = LocalAppState.current
    val context = LocalContext.current
    var settings by remember { mutableStateOf(app.account?.settings ?: UserSettings()) }
    var confirmDelete by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun update(newValue: UserSettings) {
        settings = newValue
        app.scope.launch {
            try {
                app.updateAccount(app.backend.updateSettings(newValue))
                if (newValue.pushEnabled) PushNotifications.requestAuthorization(context)
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen("Settings") {
        app.account?.let { account ->
            val name = app.artistProfile?.artistName ?: app.ownedStudio?.name ?: account.email
            FormSection {
                FormRow {
                    Box(Modifier.border(2.5.dp, Theme.neon, CircleShape).padding(2.5.dp)) {
                        Avatar(app.artistProfile?.avatarUrl, name, 56.dp)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Txt(name, style = Type.headline, maxLines = 1)
                        Txt(account.email, style = Type.subheadline, color = Theme.secondary, maxLines = 1)
                        T(account.role.title, Modifier.background(Theme.violet.copy(alpha = 0.15f), CircleShape).padding(horizontal = 8.dp, vertical = 3.dp),
                            style = Type.caption2.bold, color = Theme.violet)
                    }
                }
            }
        }

        FormSection(footer = "Language, appearance, effects and storage on this device.") {
            FormNavRow("App settings", "slider.horizontal.3", iconColors = TilePalette.ocean) { AppSettingsView() }
            FormNavRow("Change password", "key.fill", iconColors = TilePalette.signal) { ChangePasswordView() }
        }

        FormSection("Notifications") {
            FormToggle("Push notifications", settings.pushEnabled, "bell.badge.fill", iconColors = TilePalette.signal) { update(settings.copy(pushEnabled = it)) }
            FormToggle("Email notifications", settings.emailEnabled, "envelope.fill", iconColors = TilePalette.violet) { update(settings.copy(emailEnabled = it)) }
        }

        FormSection("Notify me about", footer = "Payment receipts and security messages are always sent.") {
            FormToggle("Booking updates", settings.bookingUpdates, "calendar", iconColors = TilePalette.ocean) { update(settings.copy(bookingUpdates = it)) }
            FormToggle("Messages", settings.messages, "bubble.left.and.bubble.right.fill", iconColors = TilePalette.mint) { update(settings.copy(messages = it)) }
            if (app.role == UserRole.Artist) {
                FormToggle("Session reminders", settings.reminders, "alarm.fill", iconColors = listOf(Theme.warning, Theme.accent)) { update(settings.copy(reminders = it)) }
                FormToggle("Review prompts", settings.reviewPrompts, "star.bubble.fill", iconColors = TilePalette.violet) { update(settings.copy(reviewPrompts = it)) }
            }
            FormToggle("News & offers", settings.marketing, "megaphone.fill", iconColors = TilePalette.muted) { update(settings.copy(marketing = it)) }
        }

        if (app.role == UserRole.Artist) {
            FormSection("Search") {
                var radius by remember { mutableStateOf(settings.searchRadiusKm.toFloat()) }
                Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SettingsIcon("scope", TilePalette.ocean)
                        T("Default radius", Modifier.weight(1f), style = Type.body)
                        Txt("${radius.toInt()} km", style = Type.subheadline.bold)
                    }
                    Slider(
                        radius, { radius = it }, valueRange = 1f..50f, steps = 48,
                        onValueChangeFinished = { update(settings.copy(searchRadiusKm = radius.toInt().toDouble())) },
                        colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Theme.accent, inactiveTrackColor = Theme.fill, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
                    )
                }
                Divider()
                FormToggle("Use kilometres", settings.useMetricUnits, "ruler.fill", iconColors = TilePalette.muted) { update(settings.copy(useMetricUnits = it)) }
                FormButton(if (app.location.isAuthorized) "Location allowed" else "Allow location access", "location.fill", color = Theme.primary,
                    enabled = !app.location.isAuthorized, iconColors = TilePalette.mint) { app.location.requestPermission() }
            }
        }

        FormSection("Legal") {
            FormNavRow("Terms, privacy & policies", "doc.text.fill", iconColors = TilePalette.muted) { LegalListView() }
            FormNavRow("Blocked accounts", "hand.raised.fill", iconColors = listOf(Color.Red, Theme.magenta)) { BlockedAccountsView() }
            FormNavRow("Warnings & account history", "exclamationmark.shield.fill", iconColors = listOf(Theme.warning, Theme.accent)) { AccountHistoryView() }
            app.account?.acceptedTermsAt?.let { accepted ->
                FormRow {
                    SettingsIcon("checkmark.seal.fill", TilePalette.mint)
                    T("Terms accepted", Modifier.weight(1f), style = Type.body)
                    Txt(Dates.abbreviated(accepted), style = Type.body, color = Theme.secondary)
                }
            }
        }

        FormSection("Your data", footer = "Download a copy of everything EasySesh stores about you (GDPR). Deleting your account removes your profile; receipts are kept as required by accounting law.") {
            DataExportButton()
            FormNavRow("Contact us about your data", "envelope.open.fill", iconColors = TilePalette.violet) { SupportCenterView() }
        }

        FormSection {
            FormButton("Sign out", "rectangle.portrait.and.arrow.right", color = Theme.primary, iconColors = TilePalette.muted) { app.scope.launch { app.signOut() } }
            FormButton("Delete account", "trash.fill", color = Theme.red, iconColors = listOf(Color.Red, Theme.magenta)) { confirmDelete = true }
        }
    }

    if (confirmDelete) {
        ConfirmDialog(
            "Delete your account?",
            tr("Your profile, messages and upcoming bookings will be removed. Receipts are kept for accounting as required by law."),
            listOf(DialogAction("Delete account", destructive = true) {
                app.scope.launch { try { app.deleteAccount() } catch (e: Exception) { error = e.userMessage } }
            }),
            { confirmDelete = false },
        )
    }
    ErrorAlert(error) { error = null }
}

/** People and studios you've blocked; unblocking lets you message each other again. */
@Composable
fun BlockedAccountsView() {
    val app = LocalAppState.current
    var blocked by remember { mutableStateOf<List<BlockedUser>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try { blocked = app.backend.blockedUsers() } catch (e: Exception) { error = e.userMessage }
        isLoading = false
    }

    fun unblock(user: BlockedUser) {
        app.scope.launch {
            try {
                app.backend.unblockUser(user.userId)
                blocked = blocked.filter { it.userId != user.userId }
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen("Blocked accounts") {
        if (isLoading) Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { ProgressSpinner() }
        FormSection {
            if (!isLoading && blocked.isEmpty()) FormRow { T("You haven't blocked anyone.", style = Type.body, color = Theme.secondary) }
            blocked.forEach { user ->
                FormRow {
                    Avatar(user.avatarUrl, user.displayName, 36.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Txt(user.displayName, style = Type.subheadline.semibold)
                        Txt(L10n.format("Blocked %@", Dates.abbreviated(user.blockedAt)), style = Type.caption, color = Theme.secondary)
                    }
                    LinkButton("Unblock", style = Type.subheadline.bold) { unblock(user) }
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
