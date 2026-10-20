package com.easysesh.app.ui.features

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.AppNotification
import com.easysesh.app.model.ArtistSearchResult
import com.easysesh.app.model.BlockState
import com.easysesh.app.model.Booking
import com.easysesh.app.model.ChatMessage
import com.easysesh.app.model.Conversation
import com.easysesh.app.model.ConversationRequestStatus
import com.easysesh.app.model.MessageKind
import com.easysesh.app.model.NotificationKind
import com.easysesh.app.model.ReportTarget
import com.easysesh.app.model.StudioStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.DeepLink
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

enum class ConversationFilter {
    All, Unread, Requests;

    fun title(role: UserRole) = when (this) {
        All -> tr("All")
        Unread -> tr("Unread")
        Requests -> if (role == UserRole.Artist) tr("Requests") else tr("Sent requests")
    }
}

@Composable
fun ConversationsView() {
    val app = LocalAppState.current
    var conversations by remember { mutableStateOf<List<Conversation>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var filter by remember { mutableStateOf(ConversationFilter.All) }
    var isComposing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val navigator = remember { Navigator() }
    val requests = conversations.filter { it.isPendingRequest }
    val visible = when (filter) {
        // Artists see pending requests only in the Requests folder; declined threads are hidden.
        ConversationFilter.All -> if (app.role == UserRole.Artist) conversations.filter { it.status == ConversationRequestStatus.Accepted } else conversations
        ConversationFilter.Unread -> conversations.filter { it.badgeCount(app.role) > 0 }
        ConversationFilter.Requests -> requests
    }

    suspend fun load() {
        runCatching { app.backend.conversations() }.getOrNull()?.let { conversations = it }
        app.unreadMessages = conversations.sumOf { it.badgeCount(app.role) }
        isLoading = false
        val link = app.consumeDeepLink { it is DeepLink.ConversationLink } as? DeepLink.ConversationLink
        link?.let { l -> conversations.firstOrNull { it.id == l.id }?.let { c -> navigator.push { ChatView(c) } } }
    }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(navigator.stack.size) { if (navigator.stack.isEmpty()) load() }
    LaunchedEffect(app.pendingDeepLink) { if (app.pendingDeepLink is DeepLink.ConversationLink) load() }

    fun respond(conversation: Conversation, accept: Boolean) {
        app.scope.launch {
            try {
                val updated = app.backend.respondToMessageRequest(conversation.id, accept)
                conversations = conversations.map { if (it.id == updated.id) updated else it }
            } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavigationStack(navigator) {
        val unread = conversations.sumOf { it.badgeCount(app.role) }
        EasySeshScreen("Messages", eyebrow = if (unread > 0) L10n.format("%lld unread", unread) else tr("Inbox"), refresh = { load() }, trailing = {
            if (app.role == UserRole.StudioOwner && app.ownedStudio?.status == StudioStatus.Approved) {
                GlassIconButton("square.and.pencil", "New message") { isComposing = true }
            }
        }) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ConversationFilter.entries.forEach { item ->
                    Box {
                        Chip(item.title(app.role), isSelected = filter == item, translate = false, modifier = Modifier.pressable { filter = item })
                        if (item == ConversationFilter.Requests && requests.isNotEmpty()) {
                            Txt("${requests.size}", Modifier.align(Alignment.TopEnd).offset(4.dp, (-4).dp).size(16.dp).background(Theme.accent, CircleShape),
                                style = Type.system(10, FontWeight.Bold), color = Color.White, align = TextAlign.Center)
                        }
                    }
                }
            }
            if (app.role == UserRole.Artist && filter == ConversationFilter.All && requests.isNotEmpty()) {
                GlassCard(padding = 12.dp, onClick = { filter = ConversationFilter.Requests }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconTile("tray.full.fill", 36.dp, TilePalette.violet)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            T("Message requests", style = Type.subheadline.bold)
                            Txt(if (requests.size == 1) tr("1 studio wants to talk to you") else L10n.format("%lld studios want to talk to you", requests.size), style = Type.caption, color = Theme.secondary)
                        }
                        Sym("chevron.right", size = 14.dp, tint = Theme.tertiary)
                    }
                }
            }
            if (visible.isEmpty() && !isLoading) {
                val title = when (filter) {
                    ConversationFilter.All -> "No messages yet"
                    ConversationFilter.Unread -> "You're all caught up"
                    ConversationFilter.Requests -> if (app.role == UserRole.Artist) "No message requests" else "No pending requests"
                }
                val message = if (filter == ConversationFilter.Requests) {
                    if (app.role == UserRole.Artist) "When a studio you haven't booked writes to you, it shows up here first."
                    else "Artists you message who haven't booked you yet see it as a request until they accept."
                } else {
                    if (app.role == UserRole.Artist) "Message a studio from its profile or from one of your bookings."
                    else "Artists can message you about your studio and bookings. Tap ✎ to write to an artist."
                }
                GlassEmptyState(title, if (filter == ConversationFilter.Requests) "tray" else "bubble.left.and.bubble.right.fill", message)
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                visible.forEach { conversation ->
                    var menu by remember(conversation.id) { mutableStateOf(false) }
                    Box {
                        ConversationRow(conversation, app.role, Modifier.longPressable(
                            onClick = { navigator.push { ChatView(conversation) } },
                            onLongClick = { if (app.role == UserRole.Artist && conversation.isPendingRequest) menu = true },
                        ))
                        DropdownMenu(menu, { menu = false }, containerColor = Theme.card) {
                            MenuItem("Accept", "checkmark") { menu = false; respond(conversation, true) }
                            MenuItem("Delete request", "trash", destructive = true) { menu = false; respond(conversation, false) }
                        }
                    }
                }
            }
        }
    }
    if (isComposing) {
        Sheet({ isComposing = false }) {
            NewMessageSheet { conversation ->
                conversations = listOf(conversation) + conversations.filter { it.id != conversation.id }
                navigator.push { ChatView(conversation) }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.longPressable(onClick: () -> Unit, onLongClick: () -> Unit): Modifier =
    this.clip(RoundedCornerShape(22.dp)).combinedClickable(onClick = onClick, onLongClick = onLongClick)

@Composable
fun ConversationRow(conversation: Conversation, role: UserRole, modifier: Modifier = Modifier) {
    val unread = conversation.unread(role)
    Box(modifier) {
        GlassCard(padding = 12.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.then(if (unread > 0) Modifier.neonGlow(Theme.magenta, 8.dp, CircleShape) else Modifier)
                        .border(2.5.dp, if (unread > 0) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.08f), Theme.primary.copy(alpha = 0.08f))), CircleShape)
                        .padding(2.5.dp),
                ) {
                    if (role == UserRole.Artist) RemoteImage(conversation.studioPhotoUrl, Modifier.size(52.dp).clip(CircleShape))
                    else Avatar(conversation.artistAvatarUrl, conversation.artistName, 52.dp)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(conversation.title(role), Modifier.weight(1f), style = Type.headline.copy(fontWeight = if (unread > 0) FontWeight.ExtraBold else FontWeight.SemiBold), maxLines = 1)
                        Txt(Dates.relative(conversation.lastMessageAt), style = Type.caption, color = if (unread > 0) Theme.accent else Theme.secondary)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        when {
                            conversation.isPendingRequest -> Tag(if (role == UserRole.Artist) "Request" else "Request sent", "tray")
                            conversation.isDeclined && role == UserRole.StudioOwner -> Tag("Declined", "hand.raised")
                            conversation.bookingId != null -> Sym("calendar", size = 13.dp, tint = Theme.accent)
                        }
                        Txt(conversation.lastMessagePreview.ifEmpty { tr("New conversation") }, Modifier.weight(1f), style = Type.subheadline,
                            color = if (unread > 0) Theme.primary else Theme.secondary, maxLines = 1)
                        if (unread > 0) {
                            Txt("$unread", Modifier.background(Theme.neon, CircleShape).padding(horizontal = 7.dp, vertical = 2.dp), style = Type.caption.bold, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Tag(text: String, symbol: String) {
    Row(Modifier.background(Theme.violet.copy(alpha = 0.15f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Sym(symbol, size = 11.dp, tint = Theme.violet)
        T(text, style = Type.caption2.bold, color = Theme.violet)
    }
}

/** Studio → artist: pick an artist (search, or someone who booked you) and write the first message. */
@Composable
fun NewMessageSheet(onSent: (Conversation) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<ArtistSearchResult>>(emptyList()) }
    var selected by remember { mutableStateOf<ArtistSearchResult?>(null) }
    var message by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(query) {
        delay(300)
        try { results = app.backend.searchArtists(query) } catch (e: Exception) { error = e.userMessage }
    }
    val chosen = selected
    NavScreen(
        chosen?.artistName ?: tr("New message"), translateTitle = false,
        leading = { ToolbarButton(if (chosen == null) "Cancel" else "Back") { if (chosen == null) dismiss() else selected = null } },
        actions = {
            if (chosen != null) ToolbarButton(if (isSending) "Sending…" else "Send", enabled = !isSending && message.isNotBlank(), bold = true) {
                isSending = true
                app.scope.launch {
                    try {
                        val conversation = app.backend.startConversation(chosen.id, message)
                        dismiss()
                        onSent(conversation)
                    } catch (e: Exception) { error = e.userMessage } finally { isSending = false }
                }
            }
        },
    ) {
        if (chosen == null) {
            GlassField("magnifyingglass", false) { PlainTextField(query, { query = it }, "Search artists", Modifier.weight(1f)) }
            FormSection(if (query.length < 2) "Your artists" else "Artists") {
                if (results.isEmpty()) FormContent {
                    T(if (query.length < 2) "Artists who booked you appear here. Search to find others by name or city." else "No artists found.", style = Type.subheadline, color = Theme.secondary)
                }
                results.forEach { artist ->
                    FormRow(onClick = { selected = artist }) {
                        Avatar(artist.avatarUrl, artist.artistName, 44.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(artist.artistName, style = Type.headline)
                                if (artist.isVerified) VerifiedBadge()
                                if (artist.hasAdminBadge == true) AdminBadge(compact = true)
                                if (artist.isPromoted == true) PromotedTag()
                            }
                            Txt(listOf(artist.city, artist.genres.take(2).joinToString(", ")).filter { it.isNotEmpty() }.joinToString(" · "), style = Type.caption, color = Theme.secondary)
                        }
                        if (artist.hasBooked) T("Booked you", style = Type.caption2.bold, color = Theme.positive)
                    }
                }
            }
        } else {
            FormSection {
                FormContent {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(chosen.avatarUrl, chosen.artistName, 52.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Txt(chosen.artistName, style = Type.headline)
                            T(if (chosen.hasBooked) "Goes straight to their inbox." else "They'll get it as a message request and can accept or delete it.", style = Type.caption, color = Theme.secondary)
                        }
                    }
                }
            }
            FormSection(footer = "Be personal and relevant. Studios that spam artists can be suspended.") {
                FormTextField("Write a message…", message, { message = it }, minLines = 5, maxLines = 12)
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun ChatView(initial: Conversation) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var conversation by remember { mutableStateOf(initial) }
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var draft by remember { mutableStateOf("") }
    var reporting by remember { mutableStateOf<ChatMessage?>(null) }
    var booking by remember { mutableStateOf<Booking?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var partnerAvatar by remember { mutableStateOf<String?>(null) }
    var partnerRating by remember { mutableStateOf<Pair<Double, Int>?>(null) }
    var blockState by remember { mutableStateOf(BlockState.None) }
    var confirmBlock by remember { mutableStateOf(false) }
    var reportingPartner by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val isStudio = app.role == UserRole.StudioOwner
    val partnerName = conversation.title(app.role)
    val partnerPhoto = partnerAvatar ?: if (isStudio) conversation.artistAvatarUrl else conversation.studioPhotoUrl
    val list = rememberLazyListState()

    LaunchedEffect(Unit) {
        try {
            messages = app.backend.messages(conversation.id)
            app.backend.markConversationRead(conversation.id)
            conversation.bookingId?.let { id -> booking = runCatching { app.backend.booking(id) }.getOrNull() }
        } catch (e: Exception) { error = e.userMessage }
        blockState = runCatching { app.backend.conversationBlockState(conversation.id) }.getOrDefault(BlockState.None)
        if (isStudio) {
            runCatching { app.backend.artistProfile(conversation.artistId) }.getOrNull()?.let { partnerAvatar = it.avatarUrl; partnerRating = (it.ratingAverage ?: 0.0) to (it.reviewCount ?: 0) }
        } else {
            runCatching { app.backend.studio(conversation.studioId) }.getOrNull()?.let { partnerAvatar = it.photoUrls.firstOrNull(); partnerRating = it.ratingAverage to it.reviewCount }
        }
    }
    LaunchedEffect(Unit) {
        runCatching {
            app.backend.messageStream(conversation.id).collect { message ->
                if (messages.none { it.id == message.id }) messages = messages + message
                runCatching { app.backend.markConversationRead(conversation.id) }
            }
        }
    }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) list.animateScrollToItem(messages.size + 1) }

    fun setBlocked(blocked: Boolean) {
        app.scope.launch {
            try { blockState = app.backend.setConversationBlock(conversation.id, blocked) } catch (e: Exception) { error = e.userMessage }
        }
    }

    fun send() {
        val text = draft
        draft = ""
        app.scope.launch {
            try {
                val message = app.backend.sendMessage(conversation.id, text)
                if (messages.none { it.id == message.id }) messages = messages + message
            } catch (e: Exception) {
                draft = text
                error = e.userMessage
            }
        }
    }

    fun respond(accept: Boolean) {
        app.scope.launch {
            try { conversation = app.backend.respondToMessageRequest(conversation.id, accept) } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen(
        partnerName, translateTitle = false, scrollable = false,
        titleContent = {
            NavLink({
                if (isStudio) ArtistPublicProfileView(conversation.artistId, null) else StudioDetailView(conversation.studioId, null)
            }) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(partnerPhoto, partnerName, 32.dp, Modifier.border(1.5.dp, Theme.neon, CircleShape))
                    Column {
                        Txt(partnerName, style = Type.subheadline.bold, maxLines = 1)
                        val rating = partnerRating
                        if (rating != null && rating.second > 0) {
                            Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                                Sym("star.fill", size = 11.dp, tint = Theme.accent)
                                Txt(String.format(Locale.getDefault(), "%.1f", rating.first), style = Type.caption2.bold)
                                Txt("(${rating.second})", style = Type.caption2, color = Theme.secondary)
                            }
                        } else {
                            T(if (rating == null) (if (isStudio) "View artist profile" else "View studio") else "No ratings yet", style = Type.caption2, color = Theme.secondary)
                        }
                    }
                    Sym("chevron.right", size = 12.dp, tint = Theme.tertiary)
                }
            }
        },
        actions = {
            Box {
                GlassIcon("ellipsis.circle", Modifier.pressable { menu = true })
                DropdownMenu(menu, { menu = false }, containerColor = Theme.card) {
                    MenuItem(if (isStudio) "Report artist" else "Report studio", "flag") { menu = false; reportingPartner = true }
                    if (blockState == BlockState.ByMe) MenuItem("Unblock", "hand.raised.slash") { menu = false; setBlocked(false) }
                    else MenuItem(if (isStudio) "Block artist" else "Block studio", "hand.raised.fill", destructive = true) { menu = false; confirmBlock = true }
                }
            }
        },
    ) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    booking?.let { b ->
                        NavLink({ BookingDetailView(b.id, b) }) {
                            GlassCard(cornerRadius = Theme.corner) {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Sym("calendar", size = 15.dp)
                                    Txt("${b.sessionTypeName} · ${Dates.abbreviatedWithTime(b.startsAt)}", Modifier.weight(1f), style = Type.footnote)
                                    StatusPill(b.status.title, b.status.color)
                                }
                            }
                        }
                    }
                    T("Keep payments and bookings inside EasySesh – you're protected by our refund policy.", Modifier.fillMaxWidth().padding(bottom = 8.dp),
                        style = Type.caption2, color = Theme.secondary, align = TextAlign.Center)
                }
            }
            itemsIndexed(messages, key = { _, m -> m.id }) { index, message ->
                val isMine = message.senderId == app.account?.id
                val lastInRun = index == messages.lastIndex || messages[index + 1].senderId != message.senderId
                var bubbleMenu by remember(message.id) { mutableStateOf(false) }
                Box {
                    MessageBubble(message, isMine, partnerPhoto, partnerName, !isMine && lastInRun, Modifier.longPressable(onClick = {}, onLongClick = { bubbleMenu = true }))
                    DropdownMenu(bubbleMenu, { bubbleMenu = false }, containerColor = Theme.card) {
                        MenuItem("Copy", "doc.on.doc") {
                            bubbleMenu = false
                            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("message", message.body))
                        }
                        if (message.senderId != null && message.senderId != app.account?.id) {
                            MenuItem("Report message", "flag") { bubbleMenu = false; reporting = message }
                        }
                    }
                }
            }
            item { Spacer(Modifier.size(1.dp)) }
        }
        // Bottom bar
        Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().imePadding()) {
            when {
                blockState != BlockState.None -> Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Sym("hand.raised.fill", size = 14.dp, tint = Theme.secondary)
                        T(if (blockState == BlockState.ByMe) "You blocked this account." else "You can't reply to this conversation.", style = Type.footnote.semibold, color = Theme.secondary)
                    }
                    if (blockState == BlockState.ByMe) LinkButton("Unblock", style = Type.footnote.bold) { setBlocked(false) }
                }
                app.role == UserRole.Artist && conversation.isPendingRequest -> Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Txt(L10n.format("%@ wants to send you a message", conversation.studioName), style = Type.subheadline.semibold)
                    T("Accept to reply. They won't know you've seen it until you do.", style = Type.caption, color = Theme.secondary, align = TextAlign.Center)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SecondaryButton("Delete", Modifier.weight(1f), color = Theme.red) { respond(false) }
                        PrimaryButton("Accept", Modifier.weight(1f)) { respond(true) }
                    }
                }
                app.role == UserRole.StudioOwner && conversation.isDeclined -> Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.Center) {
                    Sym("hand.raised.fill", size = 14.dp, tint = Theme.secondary)
                    HSpace(6.dp)
                    T("This artist isn't accepting messages from your studio.", style = Type.footnote, color = Theme.secondary)
                }
                else -> Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f).background(Theme.background.copy(alpha = 0.6f), RoundedCornerShape(22.dp)).border(1.dp, Theme.primary.copy(alpha = 0.1f), RoundedCornerShape(22.dp)).padding(horizontal = 14.dp, vertical = 10.dp)) {
                        PlainTextField(draft, { draft = it }, "Message", Modifier.fillMaxWidth(), maxLines = 5)
                    }
                    val canSend = draft.isNotBlank()
                    Box(Modifier.size(38.dp).alpha(if (canSend) 1f else 0.4f).neonGlow(Theme.magenta, 8.dp, CircleShape).background(Theme.neon, CircleShape).pressable(enabled = canSend) { send() }, contentAlignment = Alignment.Center) {
                        Sym("arrow.up", size = 20.dp, tint = Color.White)
                    }
                }
            }
        }
    }
    if (confirmBlock) {
        ConfirmDialog(L10n.format("Block %@?", partnerName), tr("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts."),
            listOf(DialogAction("Block", destructive = true) { setBlocked(true) }), { confirmBlock = false }, translateTitle = false)
    }
    if (reportingPartner) Sheet({ reportingPartner = false }) {
        ReportSheet(if (isStudio) ReportTarget.User else ReportTarget.Studio, if (isStudio) conversation.artistId else conversation.studioId)
    }
    reporting?.let { message -> Sheet({ reporting = null }) { ReportSheet(ReportTarget.Message, message.id) } }
    ErrorAlert(error) { error = null }
}

@Composable
fun MessageBubble(message: ChatMessage, isMine: Boolean, avatarUrl: String?, name: String, showAvatar: Boolean, modifier: Modifier = Modifier) {
    if (message.kind != MessageKind.Text) {
        Row(Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(10.dp)).padding(8.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Sym("info.circle", size = 13.dp, tint = Theme.secondary)
            HSpace(4.dp)
            Txt(message.body, style = Type.caption, color = Theme.secondary)
        }
        return
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (isMine) Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
        if (!isMine) Avatar(avatarUrl, name, 26.dp, Modifier.alpha(if (showAvatar) 1f else 0f))
        Column(modifier.weight(1f, fill = false), horizontalAlignment = if (isMine) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Txt(
                message.body,
                Modifier.background(if (isMine) Theme.neon else Brush.linearGradient(listOf(Theme.card, Theme.card)), RoundedCornerShape(20.dp)).padding(horizontal = 14.dp, vertical = 9.dp),
                style = Type.body, color = if (isMine) Color.White else Theme.primary,
            )
            Txt(Dates.time(message.createdAt), style = Type.caption2, color = Theme.secondary)
        }
        if (!isMine) Spacer(Modifier.widthIn(min = 48.dp))
    }
}

// MARK: Inbox (notifications)

@Composable
fun NotificationsView() {
    val app = LocalAppState.current
    var confirmClear by remember { mutableStateOf(false) }
    var pendingLinks by remember { mutableStateOf(setOf<String>()) }
    var linkRequest by remember { mutableStateOf<AppNotification?>(null) }
    var respondingTo by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf<AppNotification?>(null) }
    val fresh = app.notifications.filter { !it.isRead }
    val earlier = app.notifications.filter { it.isRead }

    LaunchedEffect(Unit) {
        app.refreshBadges()
        val account = app.account
        if (account != null && account.role == UserRole.Artist) {
            runCatching { app.backend.artistStudioLinks(account.id) }.getOrNull()?.let { links -> pendingLinks = links.filter { !it.isAccepted }.map { it.studioId }.toSet() }
        }
    }

    fun isLinkRequest(note: AppNotification): Boolean {
        val studioId = note.studioId ?: return false
        return note.bookingId == null && note.conversationId == null && studioId in pendingLinks
    }

    fun respond(note: AppNotification, accept: Boolean) {
        val studioId = note.studioId ?: return
        respondingTo = studioId
        app.scope.launch {
            try {
                app.backend.respondStudioArtistLink(studioId, accept)
                pendingLinks = pendingLinks - studioId
                app.markNotificationRead(note)
            } catch (e: Exception) { error = e.userMessage } finally { respondingTo = null }
        }
    }

    @Composable
    fun Row(note: AppNotification) {
        val palette = when (note.kind) {
            NotificationKind.BookingConfirmed, NotificationKind.StudioApproved, NotificationKind.PayoutSent -> TilePalette.mint
            NotificationKind.BookingCancelled, NotificationKind.BookingDeclined, NotificationKind.StudioRejected, NotificationKind.RefundIssued -> listOf(Theme.red, Theme.magenta)
            NotificationKind.NewMessage -> TilePalette.ocean
            NotificationKind.NewReview, NotificationKind.ReviewReminder -> listOf(Theme.warning, Theme.accent)
            else -> TilePalette.signal
        }
        SwipeToDelete({ app.scope.launch { app.deleteNotification(note) } }) {
            Box {
                GlassCard(padding = 14.dp, onClick = {
                    app.scope.launch { app.markNotificationRead(note) }
                    if (isLinkRequest(note)) linkRequest = note
                    else if (note.kind == NotificationKind.NewMessage && note.conversationId != null) DeepLink.from(note.conversationId, null, null)?.let { app.open(it) }
                    else reading = note
                }) {
                    androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconTile(note.kind.symbol, 40.dp, if (note.isRead) TilePalette.muted else palette)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                                T(note.title, Modifier.weight(1f), style = Type.subheadline.copy(fontWeight = if (note.isRead) FontWeight.SemiBold else FontWeight.ExtraBold), maxLines = 2)
                                Txt(Dates.relative(note.createdAt), style = Type.caption2, color = Theme.tertiary)
                            }
                            Txt(note.body, style = Type.subheadline, color = Theme.secondary, maxLines = 3)
                            if (isLinkRequest(note)) {
                                androidx.compose.foundation.layout.Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Sym("hand.tap.fill", size = 13.dp, tint = Theme.accent)
                                    T(if (respondingTo == note.studioId) "Saving…" else "Tap to connect or decline", style = Type.caption.semibold, color = Theme.accent)
                                }
                            }
                        }
                    }
                }
                if (!note.isRead) Box(Modifier.align(Alignment.TopEnd).padding(top = 8.dp, end = 8.dp).size(9.dp).neonGlow(Theme.magenta, 5.dp, CircleShape).background(Theme.neon, CircleShape))
            }
        }
    }

    NavigationStack {
        EasySeshScreen("Inbox", eyebrow = if (fresh.isEmpty()) tr("Notifications") else L10n.format("%lld new", fresh.size), refresh = { app.refreshBadges() }, trailing = {
            if (fresh.isNotEmpty()) GlassIconButton("checkmark.circle", "Mark all read") { app.scope.launch { app.markAllNotificationsRead() } }
            if (app.notifications.isNotEmpty()) GlassIconButton("trash", "Clear all") { confirmClear = true }
        }) {
            if (app.notifications.isEmpty()) GlassEmptyState("You're all caught up", "bell.badge.fill", "Bookings, messages and payouts show up here.")
            if (fresh.isNotEmpty()) {
                GlowSectionHeader("New", fresh.size)
                fresh.forEach { Row(it) }
            }
            if (earlier.isNotEmpty()) {
                GlowSectionHeader("Earlier")
                earlier.forEach { Row(it) }
            }
            if (app.notifications.isNotEmpty()) {
                androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Sym("hand.draw", size = 13.dp, tint = Theme.tertiary)
                    HSpace(4.dp)
                    T("Swipe left on a notification to delete it", style = Type.caption, color = Theme.tertiary)
                }
            }
        }
    }
    if (confirmClear) {
        ConfirmDialog("Delete all notifications?", actions = listOf(DialogAction("Delete all", destructive = true) { app.scope.launch { app.deleteAllNotifications() } }), onDismiss = { confirmClear = false })
    }
    reading?.let { note -> Sheet({ reading = null }) { NotificationDetailView(note) } }
    linkRequest?.let { note ->
        val actions = mutableListOf(DialogAction("Connect") { respond(note, true) }, DialogAction("Decline", destructive = true) { respond(note, false) })
        note.studioId?.let { id -> actions += DialogAction("View studio") { app.open(DeepLink.StudioLink(id)) } }
        ConfirmDialog(note.title, note.body, actions, { linkRequest = null })
    }
    ErrorAlert(error) { error = null }
}

/** A notification opened in full: the whole text, when it came, and a button to what it's about. */
@Composable
fun NotificationDetailView(note: AppNotification) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val link = DeepLink.from(note.conversationId, note.bookingId, note.studioId)
    val linkTitle = when {
        note.conversationId != null -> "Open chat"
        note.bookingId != null -> "View booking"
        note.studioId != null -> if (app.account?.role == UserRole.StudioOwner) "Open your studio" else "View studio"
        else -> null
    }
    NavigationStack {
        NavScreen("", leading = { ToolbarButton("Done") { dismiss() } }) {
            GlassCard(padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconTile(note.kind.symbol, 44.dp, TilePalette.signal)
                        Txt(Dates.abbreviatedWithTime(note.createdAt), style = Type.caption, color = Theme.secondary)
                    }
                    T(note.title, style = Type.title3.bold)
                    Txt(note.body, style = Type.body)
                }
            }
            if (link != null && linkTitle != null) PrimaryButton(linkTitle) { dismiss(); app.open(link) }
            if (note.kind == NotificationKind.System) FormSection { FormNavRow("Warnings & account history", "exclamationmark.shield.fill") { AccountHistoryView() } }
            T("Questions? Reply to the email or contact support.", Modifier.padding(horizontal = 4.dp), style = Type.footnote, color = Theme.secondary)
        }
    }
}

/** Warnings, restrictions and changes the EasySesh team made to the account, with the reasons. Can't be deleted. */
@Composable
fun AccountHistoryView() {
    val app = LocalAppState.current
    var moderation by remember { mutableStateOf<List<com.easysesh.app.model.ModerationRecord>>(emptyList()) }
    var changes by remember { mutableStateOf<List<com.easysesh.app.model.AccountChangeNotice>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        try {
            val history = app.backend.accountHistory()
            moderation = history.first
            changes = history.second
        } catch (e: Exception) { error = e.userMessage }
        loaded = true
    }
    NavScreen("Warnings & account history") {
        T("Warnings, restrictions and changes the EasySesh team made to your account, with the reasons.", Modifier.padding(horizontal = 4.dp), style = Type.footnote, color = Theme.secondary)
        if (loaded && moderation.isEmpty() && changes.isEmpty()) {
            GlassEmptyState("Nothing here", "checkmark.shield.fill", "You have no warnings, and the EasySesh team hasn't changed your account.")
        }
        if (moderation.isNotEmpty()) {
            FormSection("Warnings & restrictions") {
                moderation.forEach { item ->
                    FormContent {
                        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                            T(item.title, Modifier.weight(1f), style = Type.headline)
                            Txt(Dates.abbreviated(item.createdAt), style = Type.caption, color = Theme.secondary)
                        }
                        if (item.reason.isNotEmpty()) Txt(item.reason, style = Type.subheadline)
                        item.endsAt?.let { Txt(L10n.format("Until %@.", Dates.abbreviatedWithTime(it)), style = Type.caption, color = Theme.secondary) }
                    }
                }
            }
        }
        if (changes.isNotEmpty()) {
            FormSection("Account changes") {
                changes.forEach { notice ->
                    FormContent {
                        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                            T("Your account was updated", Modifier.weight(1f), style = Type.headline)
                            Txt(Dates.abbreviated(notice.createdAt), style = Type.caption, color = Theme.secondary)
                        }
                        notice.changes.forEach { Txt("• $it", style = Type.subheadline) }
                        notice.reason?.takeIf { it.isNotEmpty() }?.let { Txt(tr("Why:") + " " + it, style = Type.subheadline, color = Theme.secondary) }
                    }
                }
            }
        }
        FormSection { FormNavRow("Disagree? Contact support", "lifepreserver") { SupportCenterView() } }
    }
    ErrorAlert(error) { error = null }
}
