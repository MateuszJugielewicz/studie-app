package com.easysesh.app.ui.features

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.easysesh.app.BuildConfig
import com.easysesh.app.core.Dates
import com.easysesh.app.core.L10n
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.ChangelogEntry
import com.easysesh.app.model.ModerationWarning
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant

private sealed class Block {
    data class Heading(val level: Int, val text: String) : Block()
    data class Bullet(val text: String) : Block()
    data class Paragraph(val text: String) : Block()
}

private fun parseBlocks(markdown: String): List<Block> {
    val result = mutableListOf<Block>()
    val paragraph = mutableListOf<String>()
    fun flush() {
        if (paragraph.isNotEmpty()) result += Block.Paragraph(paragraph.joinToString(" "))
        paragraph.clear()
    }
    var inComment = false
    for (raw in markdown.lines()) {
        val line = raw.trim()
        if (inComment) { if (line.contains("-->")) inComment = false; continue }
        when {
            line.startsWith("<!--") -> { flush(); if (!line.contains("-->")) inComment = true }
            line.isEmpty() -> flush()
            line.startsWith("#") -> {
                flush()
                val level = line.takeWhile { it == '#' }.length
                result += Block.Heading(level, line.drop(level).trim())
            }
            line.startsWith("- ") || line.startsWith("* ") -> { flush(); result += Block.Bullet(line.drop(2)) }
            else -> paragraph += line
        }
    }
    flush()
    return result
}

/** **bold**, *italic*, [links](https://…) and bare https:// links. */
@Composable
fun inlineMarkdown(text: String): AnnotatedString {
    val linkColor = Theme.accent
    return buildAnnotatedString {
        val pattern = Regex("""\*\*(.+?)\*\*|\*(.+?)\*|\[(.+?)]\((.+?)\)|(https?://[^\s)]+)""")
        var last = 0
        for (match in pattern.findAll(text)) {
            append(text.substring(last, match.range.first))
            val (bold, italic, label, url, bare) = match.destructured
            when {
                bold.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(bold) }
                italic.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(italic) }
                label.isNotEmpty() -> withLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = linkColor)))) { append(label) }
                else -> withLink(LinkAnnotation.Url(bare, TextLinkStyles(SpanStyle(color = linkColor)))) { append(bare) }
            }
            last = match.range.last + 1
        }
        append(text.substring(last))
    }
}

/** Renders a bundled Markdown legal document (headings, bullets, paragraphs with inline formatting). */
@Composable
fun LegalDocumentView(document: LegalDocument, onAppear: () -> Unit = {}) {
    val context = LocalContext.current
    val language = LocalAppState.current.preferences.language
    LaunchedEffect(Unit) { onAppear() }
    val blocks = remember(language) { parseBlocks(document.markdown(context, language.code)) }
    NavScreen(document.title) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            blocks.forEach { block ->
                when (block) {
                    is Block.Heading -> Text(inlineMarkdown(block.text), Modifier.padding(top = if (block.level == 1) 0.dp else 8.dp),
                        style = (when (block.level) { 1 -> Type.title.bold; 2 -> Type.title3.bold; else -> Type.headline }).copy(color = Theme.primary))
                    is Block.Bullet -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Txt("•", style = Type.body)
                        Text(inlineMarkdown(block.text), style = Type.body.copy(color = Theme.primary))
                    }
                    is Block.Paragraph -> Text(inlineMarkdown(block.text), style = Type.body.copy(color = Theme.primary))
                }
            }
        }
    }
}

@Composable
fun LegalListView() {
    val app = LocalAppState.current
    NavScreen("Legal") {
        val footer = if (BuildConfig.SUPPORT_EMAIL.isNotEmpty()) L10n.format("Version %@. Questions? %@", app.requiredTermsVersion, BuildConfig.SUPPORT_EMAIL)
        else L10n.format("Version %@. Questions? Write to us in Settings → Support.", app.requiredTermsVersion)
        FormSection(footer = footer, translate = false) {
            LegalDocument.entries.forEach { document ->
                FormNavRow(document.title, document.symbol) { LegalDocumentView(document) }
            }
        }
    }
}

/**
 * Shown when the signed-in user hasn't accepted the current terms (new account via Google/Apple,
 * or after a legal update). Every document has to be opened before the user can accept.
 */
@Composable
fun TermsAcceptanceView() {
    val app = LocalAppState.current
    var opened by remember { mutableStateOf(setOf<LegalDocument>()) }
    var agreed by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val documents = LegalDocument.required(app.role)
    val isUpdate = app.account?.acceptedTermsVersion != null
    val allRead = documents.all { it in opened }

    NavigationStack {
        NavScreen("", leading = { ToolbarButton("Sign out") { app.scope.launch { app.signOut() } } }, auroraHeight = 360.dp) {
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                EasySeshLogo(22)
                T(if (isUpdate) "We've updated our terms" else "Before you start", style = Type.system(30, FontWeight.ExtraBold).tracking(-0.6f))
                T(if (isUpdate) "Please read the updated documents again and accept them to keep using EasySesh."
                else "Please read and accept the documents below to use EasySesh.", style = Type.body, color = Theme.secondary)
            }
            app.pendingLegalUpdate?.let { update ->
                GlassCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Sym("sparkles", size = 14.dp, tint = Theme.accent)
                        Txt(tr("What changed").uppercase(), style = Type.caption.heavy, color = Theme.accent)
                    }
                    T(update.title, style = Type.headline)
                    if (update.body.isNotEmpty()) Txt(update.body, style = Type.subheadline, color = Theme.secondary)
                }
            }
            GlassCard(padding = 12.dp) {
                documents.forEachIndexed { index, document ->
                    val read = document in opened
                    NavLink({ LegalDocumentView(document) { opened = opened + document } }) {
                        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            IconTile(document.symbol, 36.dp, if (read) TilePalette.mint else TilePalette.violet)
                            Column(Modifier.weight(1f)) {
                                T(document.title, style = Type.subheadline.semibold)
                                T(if (read) "Read" else "Tap to read", style = Type.caption, color = Theme.secondary)
                            }
                            Sym(if (read) "checkmark.circle.fill" else "chevron.right", tint = if (read) Theme.positive else Theme.secondary)
                        }
                    }
                    if (index != documents.lastIndex) Divider()
                }
            }
            GlassCard(padding = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    T("I have read and accept these documents", Modifier.weight(1f), style = Type.subheadline.semibold, color = if (allRead) Theme.primary else Theme.secondary)
                    Switch(agreed, { agreed = it }, enabled = allRead, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.White))
                }
            }
            if (!allRead) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Sym("hand.point.up.left.fill", size = 14.dp, tint = Theme.secondary)
                    T("Open each document to continue.", style = Type.caption, color = Theme.secondary)
                }
            }
            PrimaryButton(if (isSaving) "Saving…" else "Accept and continue", enabled = agreed && allRead && !isSaving) {
                isSaving = true
                app.scope.launch {
                    try { app.updateAccount(app.backend.acceptTerms(app.requiredTermsVersion)) } catch (e: Exception) { error = e.userMessage }
                    isSaving = false
                }
            }
            T("We record the version and time of your acceptance. You can withdraw consent by deleting your account in Settings.", style = Type.caption, color = Theme.tertiary)
        }
    }
    ErrorAlert(error) { error = null }
}

/** A warning from the EasySesh team. It stays until the user confirms they've read it. */
@Composable
fun WarningSheet(warning: ModerationWarning) {
    val app = LocalAppState.current
    var isSaving by remember { mutableStateOf(false) }
    NavScreen("", auroraHeight = 300.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile("exclamationmark.triangle.fill", 48.dp, TilePalette.signal)
            Column {
                T("Warning from EasySesh", style = Type.title3.heavy)
                Txt(Dates.abbreviatedWithTime(warning.createdAt), style = Type.caption, color = Theme.secondary)
            }
        }
        GlassCard { Txt(warning.reason, style = Type.body) }
        T("Please follow our Community Guidelines. Further breaches can lead to your account being suspended or banned.", style = Type.subheadline, color = Theme.secondary)
        NavLink({ LegalDocumentView(LegalDocument.CommunityGuidelines) }) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Sym("person.3.fill", tint = Theme.accent)
                T("Read the Community Guidelines", style = Type.subheadline.semibold, color = Theme.accent)
            }
        }
        PrimaryButton("I understand", enabled = !isSaving) {
            isSaving = true
            app.scope.launch { app.acknowledgeWarning(warning); isSaving = false }
        }
    }
}

/** "What's new": update notes from the EasySesh team, shown once after they're published. */
@Composable
fun WhatsNewSheet(entries: List<ChangelogEntry>) {
    val dismiss = LocalDismiss.current
    NavScreen("", auroraHeight = 300.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile("sparkles", 44.dp, TilePalette.violet)
            T("What's new", style = Type.system(30, FontWeight.ExtraBold).tracking(-0.6f))
        }
        entries.forEach { ChangelogCard(it) }
        PrimaryButton("Got it") { dismiss() }
    }
}

@Composable
private fun ChangelogCard(entry: ChangelogEntry) {
    GlassCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(entry.version, style = Type.caption.heavy, color = Theme.accent)
            if (entry.isLegalUpdate) {
                T("Legal update", Modifier.background(Theme.violet.copy(alpha = 0.15f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp), style = Type.caption2.bold, color = Theme.violet)
            }
            Fill()
            Txt(Dates.abbreviated(entry.publishedAt), style = Type.caption2, color = Theme.tertiary)
        }
        T(entry.title, style = Type.headline)
        if (entry.body.isNotEmpty()) Txt(entry.body, style = Type.subheadline, color = Theme.secondary)
    }
}

/** All update notes, for Settings. */
@Composable
fun ChangelogView() {
    val app = LocalAppState.current
    LaunchedEffect(Unit) { app.refreshUpdates() }
    NavScreen("What's new", auroraHeight = 300.dp) {
        if (app.changelog.isEmpty()) GlassEmptyState("No updates yet", "sparkles", "Update notes from the EasySesh team show up here.")
        app.changelog.forEach { ChangelogCard(it) }
    }
}

/**
 * GDPR: lets the user download everything EasySesh stores about them. One tap builds the file
 * and opens the share sheet (save to Files, Drive, mail…).
 */
@Composable
fun DataExportButton() {
    val app = LocalAppState.current
    val context = LocalContext.current
    var file by remember { mutableStateOf<File?>(null) }
    var isExporting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun share(target: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", target)
        val intent = Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(intent, null))
    }

    FormRow(onClick = if (isExporting) null else ({
        val existing = file
        if (existing != null) share(existing) else {
            isExporting = true
            app.scope.launch {
                try {
                    val json = app.backend.exportPersonalData()
                    val dir = File(context.cacheDir, "exports").apply { mkdirs() }
                    val target = File(dir, "easysesh-data-${Dates.iso(Instant.now())}.json")
                    target.writeText(json)
                    file = target
                    share(target)
                } catch (e: Exception) { error = e.userMessage }
                isExporting = false
            }
        }
    })) {
        SettingsIcon(if (file == null) "arrow.down.doc.fill" else "square.and.arrow.up.fill", if (file == null) TilePalette.ocean else TilePalette.mint)
        T(if (isExporting) "Preparing…" else if (file == null) "Download my data" else "Share my data file", Modifier.weight(1f), style = Type.body)
        if (isExporting) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Theme.secondary)
    }
    ErrorAlert(error) { error = null }
}

/** Small gradient icon used in settings rows. */
@Composable
fun SettingsIcon(symbol: String, colors: List<Color>) = IconTile(symbol, 30.dp, colors)
