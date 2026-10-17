package com.easysesh.app.ui.features

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.Booking
import com.easysesh.app.model.SupportCategory
import com.easysesh.app.model.SupportMessage
import com.easysesh.app.model.SupportTicket
import com.easysesh.app.model.SupportTicketStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch

/** "Contact support": the user's requests to the EasySesh team, answered from the admin dashboard. */
@Composable
fun SupportCenterView(booking: Booking? = null) {
    val app = LocalAppState.current
    val navigator = LocalNavigator.current
    var tickets by remember { mutableStateOf<List<SupportTicket>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var isComposing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val active = tickets.filter { it.status != SupportTicketStatus.Closed }
    val closed = tickets.filter { it.status == SupportTicketStatus.Closed }

    suspend fun load() {
        try { tickets = app.backend.supportTickets() } catch (e: Exception) { error = e.userMessage }
        isLoading = false
    }
    LaunchedEffect(Unit) { load() }
    val replace: (SupportTicket) -> Unit = { updated -> tickets = tickets.map { if (it.id == updated.id) updated else it } }

    NavScreen("Help & support") {
        FormSection {
            FormRow(onClick = { isComposing = true }) {
                IconTile("bubble.left.and.text.bubble.right.fill", 44.dp, TilePalette.signal)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    T("Contact support", style = Type.headline)
                    T("We usually reply within 24 hours.", style = Type.subheadline, color = Theme.secondary)
                }
                Sym("plus.circle.fill", size = 26.dp, tint = Theme.accent)
            }
        }

        if (active.isNotEmpty()) {
            FormSection("Active") {
                active.forEach { ticket ->
                    FormRow(onClick = { navigator?.push { SupportTicketView(ticket, replace) } }) {
                        SupportTicketRow(ticket, Modifier.weight(1f))
                        Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
                    }
                }
            }
        } else if (!isLoading) {
            FormSection {
                FormRow {
                    T("Questions about a booking, a payment or your account? Send us a message and the EasySesh team will answer here.",
                        style = Type.subheadline, color = Theme.secondary)
                }
            }
        } else {
            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { ProgressSpinner() }
        }

        if (closed.isNotEmpty()) {
            FormSection {
                FormRow(onClick = { navigator?.push { ClosedSupportTicketsView(closed, replace) } }) {
                    SettingsIcon("archivebox.fill", TilePalette.muted)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        T("Closed", style = Type.body)
                        val unrated = closed.count { it.rating == null }
                        if (unrated > 0) Txt(L10n.format("%lld waiting for your rating", unrated), style = Type.caption, color = Theme.accent)
                    }
                    Txt("${closed.size}", style = Type.body, color = Theme.secondary)
                    Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
                }
            }
        }

        FormSection("Policies") {
            FormRow(onClick = { navigator?.push { LegalDocumentView(LegalDocument.Refunds) } }) {
                SettingsIcon("arrow.uturn.backward.circle.fill", TilePalette.ocean)
                T("Refund & cancellation policy", Modifier.weight(1f), style = Type.body)
                Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
            }
            FormRow(onClick = { navigator?.push { LegalListView() } }) {
                SettingsIcon("doc.text.fill", TilePalette.muted)
                T("Terms & privacy", Modifier.weight(1f), style = Type.body)
                Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
            }
        }
    }

    if (isComposing) Sheet({ isComposing = false }) {
        NewSupportTicketView(booking) { ticket -> tickets = listOf(ticket) + tickets }
    }
    ErrorAlert(error) { error = null }
}

@Composable
private fun SupportTicketRow(ticket: SupportTicket, modifier: Modifier = Modifier) {
    Row(modifier.padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.width(28.dp).padding(top = 2.dp), contentAlignment = Alignment.Center) { Sym(ticket.category.symbol, size = 18.dp, tint = Theme.accent) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Txt(ticket.subject, Modifier.weight(1f), style = Type.subheadline.weight(if (ticket.userUnread > 0) FontWeight.Bold else FontWeight.SemiBold), maxLines = 1)
                Txt(Dates.relative(ticket.lastMessageAt), style = Type.caption, color = Theme.tertiary)
            }
            Txt(ticket.lastMessagePreview, style = Type.subheadline, color = Theme.secondary, maxLines = 2)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                StatusPill(tr(ticket.status.title), ticket.status.color)
                if (ticket.userUnread > 0) Box(Modifier.size(8.dp).background(Theme.accent, CircleShape))
            }
        }
    }
}

val SupportTicketStatus.color: Color
    @Composable get() = when (this) {
        SupportTicketStatus.Open -> Theme.warning
        SupportTicketStatus.Answered -> Theme.positive
        SupportTicketStatus.Closed -> Theme.secondary
    }

@Composable
fun NewSupportTicketView(booking: Booking?, onCreated: (SupportTicket) -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val bookingSubject = booking?.let { "Booking ${it.reference}" }
    var category by remember { mutableStateOf(if (booking != null) SupportCategory.Booking else SupportCategory.Other) }
    var subject by remember { mutableStateOf(bookingSubject ?: "") }
    var message by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val canSend = subject.trim().length >= 3 && message.trim().length >= 10 && !isSending
    val categories = if (app.role == UserRole.StudioOwner) SupportCategory.entries else SupportCategory.entries.filter { it != SupportCategory.Studio }

    fun send() {
        isSending = true
        app.scope.launch {
            try {
                val ticket = app.backend.createSupportTicket(subject, category, message, booking?.id)
                onCreated(ticket)
                dismiss()
            } catch (e: Exception) { error = e.userMessage }
            isSending = false
        }
    }

    NavScreen(
        "Contact support",
        leading = { ToolbarButton("Cancel") { dismiss() } },
        actions = { ToolbarButton(if (isSending) "Sending…" else "Send", enabled = canSend, bold = true) { send() } },
    ) {
        FormSection("What's it about?") {
            FormPicker("Topic", category, categories, { it.title }, symbol = category.symbol) { category = it }
        }
        booking?.let { b ->
            FormSection("Booking") {
                FormRow { InfoRow("calendar", b.reference, "${b.studioName} · ${Dates.abbreviatedWithTime(b.startsAt)}", translateTitle = false) }
            }
        }
        FormSection(footer = "Please don't share card numbers or passwords. The EasySesh team can see your account and bookings.") {
            FormTextField("Subject", subject, { subject = it })
            FormTextField("Describe what happened…", message, { message = it }, minLines = 6, maxLines = 14)
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
fun SupportTicketView(initial: SupportTicket, onChange: (SupportTicket) -> Unit = {}) {
    val app = LocalAppState.current
    var ticket by remember { mutableStateOf(initial) }
    var messages by remember { mutableStateOf<List<SupportMessage>>(emptyList()) }
    var draft by remember { mutableStateOf("") }
    var confirmClose by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val list = rememberLazyListState()

    LaunchedEffect(Unit) {
        try {
            messages = app.backend.supportMessages(ticket.id)
            if (ticket.userUnread > 0) {
                app.backend.markSupportTicketRead(ticket.id)
                ticket = ticket.copy(userUnread = 0)
                onChange(ticket)
            }
        } catch (e: Exception) { error = e.userMessage }
    }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) list.animateScrollToItem(messages.size) }

    fun update(updated: SupportTicket) { ticket = updated; onChange(updated) }

    fun send() {
        val text = draft
        draft = ""
        app.scope.launch {
            try {
                val message = app.backend.sendSupportMessage(ticket.id, text)
                messages = messages + message
                update(ticket.copy(status = SupportTicketStatus.Open, lastMessagePreview = message.body.take(140), lastMessageAt = message.createdAt))
            } catch (e: Exception) {
                draft = text
                error = e.userMessage
            }
        }
    }

    fun close() {
        app.scope.launch {
            try { update(app.backend.closeSupportTicket(ticket.id)) } catch (e: Exception) { error = e.userMessage }
        }
    }

    NavScreen(
        "Support", scrollable = false,
        actions = {
            if (ticket.status != SupportTicketStatus.Closed) {
                Box {
                    GlassIcon("ellipsis.circle", Modifier.pressable { menu = true })
                    DropdownMenu(menu, { menu = false }, containerColor = Theme.card) {
                        MenuItem("Mark as solved", "checkmark.circle") { menu = false; confirmClose = true }
                    }
                }
            }
        },
    ) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Column(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Sym(ticket.category.symbol, size = 26.dp, tint = Theme.accent)
                    Txt(ticket.subject, style = Type.headline, align = TextAlign.Center)
                    StatusPill(tr(ticket.status.title), ticket.status.color)
                }
            }
            items(messages, key = { it.id }) { SupportBubble(it) }
            item {
                AnimatedVisibility(ticket.status == SupportTicketStatus.Closed) {
                    Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SupportRatingCard(ticket) { update(it) }
                        T("This request is closed. Send a message to reopen it.", style = Type.caption, color = Theme.secondary, align = TextAlign.Center)
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().imePadding().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.weight(1f).background(Theme.background.copy(alpha = 0.6f), RoundedCornerShape(22.dp)).border(1.dp, Theme.primary.copy(alpha = 0.1f), RoundedCornerShape(22.dp)).padding(horizontal = 14.dp, vertical = 10.dp)) {
                PlainTextField(draft, { draft = it }, "Message", Modifier.fillMaxWidth(), maxLines = 5)
            }
            val canSend = draft.isNotBlank()
            Box(Modifier.size(38.dp).alpha(if (canSend) 1f else 0.4f).neonGlow(Theme.magenta, 8.dp, CircleShape).background(Theme.neon, CircleShape).pressable(enabled = canSend) { send() }, contentAlignment = Alignment.Center) {
                Sym("arrow.up", size = 20.dp, tint = Color.White)
            }
        }
    }
    if (confirmClose) ConfirmDialog("Close this request?", actions = listOf(DialogAction("Mark as solved") { close() }), onDismiss = { confirmClose = false })
    ErrorAlert(error) { error = null }
}

@Composable
private fun SupportBubble(message: SupportMessage) {
    Row(Modifier.fillMaxWidth()) {
        if (!message.fromAdmin) Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
        Column(Modifier.weight(1f, fill = false), horizontalAlignment = if (message.fromAdmin) Alignment.Start else Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (message.fromAdmin) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    EasySeshLogo(11)
                    T("support", style = Type.caption2.semibold, color = Theme.secondary)
                }
            }
            Txt(
                message.body,
                Modifier.background(if (message.fromAdmin) Brush.linearGradient(listOf(Theme.card, Theme.card)) else Theme.neon, RoundedCornerShape(20.dp)).padding(horizontal = 14.dp, vertical = 9.dp),
                style = Type.body, color = if (message.fromAdmin) Theme.primary else Theme.onAccent,
            )
            Txt(Dates.abbreviatedWithTime(message.createdAt), style = Type.caption2, color = Theme.secondary)
        }
        if (message.fromAdmin) Spacer(Modifier.weight(1f).widthIn(min = 48.dp))
    }
}

/** The "Closed" folder: finished requests and their ratings. */
@Composable
fun ClosedSupportTicketsView(initial: List<SupportTicket>, onChange: (SupportTicket) -> Unit = {}) {
    val navigator = LocalNavigator.current
    var tickets by remember { mutableStateOf(initial) }
    NavScreen("Closed") {
        FormSection {
            tickets.forEach { ticket ->
                FormRow(onClick = {
                    navigator?.push {
                        SupportTicketView(ticket) { updated ->
                            tickets = tickets.map { if (it.id == updated.id) updated else it }
                            onChange(updated)
                        }
                    }
                }) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SupportTicketRow(ticket)
                        val rating = ticket.rating
                        Box(Modifier.padding(start = 40.dp)) {
                            if (rating != null) StarsView(rating, 12.dp)
                            else Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Sym("star.bubble", size = 13.dp, tint = Theme.accent)
                                T("Rate this request", style = Type.caption.semibold, color = Theme.accent)
                            }
                        }
                    }
                    Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
                }
            }
        }
    }
}

/** Shown in a closed request: rate how support handled it. */
@Composable
fun SupportRatingCard(ticket: SupportTicket, onChange: (SupportTicket) -> Unit) {
    val app = LocalAppState.current
    var rating by remember { mutableStateOf(0) }
    var comment by remember { mutableStateOf("") }
    var isEditing by remember { mutableStateOf(false) }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val given = ticket.rating

    fun send() {
        isSending = true
        app.scope.launch {
            try {
                onChange(app.backend.rateSupportTicket(ticket.id, rating, comment.trim()))
                isEditing = false
            } catch (e: Exception) { error = e.userMessage }
            isSending = false
        }
    }

    GlassCard(padding = 16.dp, cornerRadius = 22.dp) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (given != null && !isEditing) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        T("Thanks for your feedback!", style = Type.subheadline.bold)
                        StarsView(given, 16.dp)
                        val text = ticket.ratingComment
                        if (!text.isNullOrEmpty()) Txt("“$text”", style = Type.subheadline, color = Theme.secondary)
                    }
                    LinkButton("Edit") {
                        rating = given
                        comment = ticket.ratingComment ?: ""
                        isEditing = true
                    }
                }
            } else {
                T("How did we do?", style = Type.headline)
                T("Rate how the EasySesh team handled your request.", style = Type.subheadline, color = Theme.secondary)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
                    (1..5).forEach { star ->
                        val scale by animateFloatAsState(if (star == rating) 1.18f else 1f, spring(dampingRatio = 0.5f), label = "star")
                        Sym(
                            if (star <= rating) "star.fill" else "star",
                            Modifier.scale(scale).neonGlow(Theme.magenta, 6.dp, CircleShape, active = star <= rating).pressable(haptic = true) { rating = star },
                            size = 30.dp, tint = if (star <= rating) Theme.accent else Theme.secondary.copy(alpha = 0.5f),
                        )
                    }
                }
                Box(Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.78f), RoundedCornerShape(14.dp)).padding(12.dp)) {
                    PlainTextField(comment, { comment = it }, "Anything we could do better? (optional)", Modifier.fillMaxWidth(), minLines = 2, maxLines = 5)
                }
                PrimaryButton(if (isSending) "Sending…" else "Send rating", Modifier.fillMaxWidth(), enabled = rating > 0 && !isSending) { send() }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
