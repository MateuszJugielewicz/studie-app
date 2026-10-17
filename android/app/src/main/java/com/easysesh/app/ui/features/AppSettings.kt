package com.easysesh.app.ui.features

import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.BuildConfig
import com.easysesh.app.core.PasswordPolicy
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.StudioStatus
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.AppAppearance
import com.easysesh.app.services.AppCache
import com.easysesh.app.services.AppLanguage
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

/** Device settings for artists and studios: language, look, effects, cache, tutorials. */
@Composable
fun AppSettingsView() {
    val app = LocalAppState.current
    val preferences = app.preferences
    val context = LocalContext.current
    var cacheSize by remember { mutableStateOf(AppCache.size(context)) }
    var confirmClear by remember { mutableStateOf(false) }
    var cleared by remember { mutableStateOf(false) }

    NavScreen("App settings") {
        FormSection {
            FormNavRow("Language", value = "${preferences.language.flag} ${preferences.language.nativeName}", iconColors = TilePalette.ocean, symbol = "globe") {
                LanguagePickerView()
            }
        }

        FormSection("Look & feel", footer = "Reduce visual effects turns off moving backgrounds and pulsing animations. It can also save battery.") {
            FormPicker("Appearance", preferences.appearance, AppAppearance.entries, { it.title }, symbol = "circle.lefthalf.filled", iconColors = TilePalette.violet) { preferences.updateAppearance(it) }
            FormToggle("Reduce visual effects", preferences.reduceEffects, "sparkles", iconColors = TilePalette.signal) { preferences.updateReduceEffects(it) }
            FormToggle("Haptics", preferences.hapticsEnabled, "iphone.radiowaves.left.and.right", iconColors = TilePalette.mint) { preferences.updateHaptics(it) }
        }

        FormSection("Storage", footer = "Photos are downloaded again when you need them. Your account, bookings and messages are not affected.") {
            FormRow {
                SettingsIcon("internaldrive", TilePalette.muted)
                T("Cached images & data", Modifier.weight(1f), style = Type.body)
                Txt(Formatter.formatShortFileSize(context, cacheSize), style = Type.body, color = Theme.secondary)
            }
            FormButton(if (cleared) "Cache cleared" else "Clear cache", "trash", color = Theme.red, enabled = cacheSize > 0, iconColors = listOf(Color.Red, Theme.magenta)) {
                confirmClear = true
            }
        }

        FormSection("Tutorials") {
            FormButton("Show the intro again", "play.rectangle.on.rectangle", color = Theme.primary, iconColors = TilePalette.signal) {
                preferences.updateHasSeenIntro(false)
            }
            val studio = app.ownedStudio
            if (app.role == UserRole.StudioOwner && studio != null && studio.status == StudioStatus.Approved) {
                FormButton("Replay the studio tour", "wand.and.stars", color = Theme.primary, iconColors = TilePalette.violet) {
                    preferences.resetTour(studio.id)
                    app.selectTab(AppTab.Dashboard)
                }
            }
        }

        FormSection("About") {
            FormRow {
                T("Version", Modifier.weight(1f), style = Type.body)
                Txt(appVersion(), style = Type.body, color = Theme.secondary)
            }
            FormNavRow("What's new") { ChangelogView() }
            FormNavRow("Terms, privacy & policies") { LegalListView() }
        }
    }

    if (confirmClear) {
        ConfirmDialog("Clear cached images and data?", actions = listOf(DialogAction("Clear cache", destructive = true) {
            AppCache.clear(context)
            cacheSize = AppCache.size(context)
            cleared = true
        }), onDismiss = { confirmClear = false })
    }
    LaunchedEffect(Unit) { cacheSize = AppCache.size(context) }
}

fun appVersion() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

@Composable
fun LanguagePickerView() {
    val preferences = LocalAppState.current.preferences
    val haptics = LocalHapticFeedback.current
    NavScreen("Language") {
        FormSection(footer = "Most text changes right away. A few system texts update the next time you open the app.") {
            AppLanguage.entries.forEach { language ->
                FormRow(onClick = {
                    preferences.updateLanguage(language)
                    if (preferences.hapticsEnabled) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                }) {
                    Txt(language.flag, style = Type.title2)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Txt(language.nativeName, style = Type.body)
                        val local = Locale.forLanguageTag(language.code).getDisplayLanguage(Locale.getDefault())
                            .replaceFirstChar { it.titlecase(Locale.getDefault()) }
                        Txt(local.ifEmpty { language.nativeName }, style = Type.caption, color = Theme.secondary)
                    }
                    AnimatedVisibility(preferences.language == language, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                        Sym("checkmark.circle.fill", size = 20.dp, tint = Theme.accent)
                    }
                }
            }
        }
    }
}

/** Choose a new password: from Settings, or after opening a password-reset link. */
@Composable
fun ChangePasswordView(isRecovery: Boolean = false) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    val haptics = LocalHapticFeedback.current
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val problem: String? = when {
        password.isEmpty() -> null
        PasswordPolicy.problem(password) != null -> PasswordPolicy.problem(password)
        confirmation.isNotEmpty() && confirmation != password -> tr("The passwords don't match.")
        else -> null
    }
    val canSave = !isSaving && PasswordPolicy.problem(password) == null && password == confirmation

    fun save() {
        isSaving = true
        app.scope.launch {
            try {
                app.backend.changePassword(password)
                saved = true
                if (app.preferences.hapticsEnabled) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                delay(1000)
                if (isRecovery) app.needsNewPassword = false else dismiss()
            } catch (e: Exception) { error = e.userMessage }
            isSaving = false
        }
    }

    NavScreen(
        "Change password",
        leading = if (isRecovery) ({ ToolbarButton("Later") { app.needsNewPassword = false } }) else null,
    ) {
        FormSection {
            FormRow {
                Crossfade(saved, label = "icon") { done ->
                    IconTile(if (done) "checkmark.shield.fill" else "key.fill", 44.dp, if (done) TilePalette.mint else TilePalette.signal)
                }
                T(if (isRecovery) "Choose a new password for your account." else "Use at least 10 characters with upper- and lowercase letters and a number.",
                    Modifier.weight(1f), style = Type.subheadline, color = Theme.secondary)
            }
        }
        FormSection(footer = problem, translate = false, footerColor = Theme.warning) {
            FormTextField("New password", password, { password = it }, capitalization = KeyboardCapitalization.None, secure = true)
            FormTextField("Repeat new password", confirmation, { confirmation = it }, capitalization = KeyboardCapitalization.None, secure = true)
        }
        FormSection {
            FormRow(onClick = if (canSave && !saved) ({ save() }) else null) {
                Box(Modifier.fillMaxWidth().padding(vertical = 2.dp), contentAlignment = Alignment.Center) {
                    if (isSaving) ProgressSpinner()
                    else T(if (saved) "Password changed" else "Save new password", style = Type.body.bold, color = if (canSave && !saved) Theme.accent else Theme.secondary)
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
