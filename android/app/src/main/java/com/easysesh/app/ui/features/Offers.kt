package com.easysesh.app.ui.features

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.L10n
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.PromoCode
import com.easysesh.app.model.Studio
import com.easysesh.app.model.StudioOffer
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Studio offers ("Mixing 50% off", applied automatically) and the studio's own promo codes. Both come
 * off the studio's price; EasySesh's fee is calculated on the discounted price. End dates are set on
 * the website.
 */
@Composable
fun StudioOffersView(studio: Studio) {
    val app = LocalAppState.current
    var offers by remember { mutableStateOf<List<StudioOffer>>(emptyList()) }
    var codes by remember { mutableStateOf<List<PromoCode>>(emptyList()) }
    var editingOffer by remember { mutableStateOf<StudioOffer?>(null) }
    var editingCode by remember { mutableStateOf<PromoCode?>(null) }
    var removing by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        try {
            offers = app.backend.studioOffers(studio.id)
            codes = app.backend.promoCodes(studio.id)
        } catch (e: Exception) { error = e.userMessage }
    }
    fun run(action: suspend () -> Unit) {
        app.scope.launch {
            try { action() } catch (e: Exception) { error = e.userMessage }
            reload()
        }
    }
    LaunchedEffect(studio.id) { reload() }
    val switchColors = SwitchDefaults.colors(checkedTrackColor = Theme.positive, checkedThumbColor = Color.White)

    NavScreen("Offers & promo codes") {
        FormSection("Offers", footer = "Offers are applied automatically when artists book, and shown on your studio page. If several match, the biggest one is used.") {
            offers.forEach { offer ->
                FormRow(onClick = { editingOffer = offer }) {
                    OfferRowContent(offer, studio)
                    Switch(offer.isActive, { on -> run { app.backend.saveOffer(offer.copy(isActive = on)) } }, colors = switchColors)
                    TextButton(onClick = { removing = offer.id to true }) { Sym("trash", size = 18.dp, tint = Theme.red) }
                }
            }
            FormButton("New offer", symbol = "plus") {
                editingOffer = StudioOffer(id = UUID.randomUUID().toString(), studioId = studio.id, title = "", percentOff = 20)
            }
        }
        FormSection("Promo codes", footer = "Give a code to artists (on social media, to regulars…). They type it in at checkout to get the discount.") {
            codes.forEach { code ->
                FormRow(onClick = { editingCode = code }) {
                    Column(Modifier.weight(1f)) {
                        Txt("${code.code} · −${code.percentOff}%", style = Type.subheadline.semibold)
                        Txt(code.maxUses?.let { L10n.format("Used %lld of %lld", code.uses, it) } ?: L10n.format("Used %lld times", code.uses),
                            style = Type.caption, color = Theme.secondary)
                    }
                    Switch(code.isActive, { on -> run { app.backend.savePromoCode(code.copy(isActive = on)) } }, colors = switchColors)
                    TextButton(onClick = { removing = code.id to false }) { Sym("trash", size = 18.dp, tint = Theme.red) }
                }
            }
            FormButton("New promo code", symbol = "plus") {
                editingCode = PromoCode(id = UUID.randomUUID().toString(), studioId = studio.id, code = "", percentOff = 10, uses = -1)
            }
        }
        T("Discounts come off your price. EasySesh's platform fee is calculated on the discounted price.",
            Modifier.padding(horizontal = 16.dp), style = Type.footnote, color = Theme.secondary)
    }

    editingOffer?.let { offer -> Sheet({ editingOffer = null }) { OfferEditor(studio, offer) { app.scope.launch { reload() } } } }
    editingCode?.let { code -> Sheet({ editingCode = null }) { PromoCodeEditor(code) { app.scope.launch { reload() } } } }
    removing?.let { (id, isOffer) ->
        ConfirmDialog(if (isOffer) "Delete this offer?" else "Delete this promo code?", onDismiss = { removing = null },
            actions = listOf(DialogAction("Delete", destructive = true) {
                run { if (isOffer) app.backend.removeOffer(id) else app.backend.removePromoCode(id) }
            }))
    }
    ErrorAlert(error) { error = null }
}

private val TARGETS = listOf("everything", "sessions", "add_ons", "session_type", "add_on")
private val TARGET_TITLES = mapOf(
    "everything" to "Everything", "sessions" to "All sessions", "add_ons" to "All extras", "session_type" to "One session type", "add_on" to "One extra",
)

@Composable
private fun OfferEditor(studio: Studio, initial: StudioOffer, onSaved: () -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var offer by remember { mutableStateOf(initial) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val needsTarget = offer.appliesTo == "session_type" || offer.appliesTo == "add_on"
    val valid = offer.title.trim().length >= 2 && (!needsTarget || offer.targetId != null)

    NavScreen(if (initial.title.isEmpty()) "New offer" else "Edit offer", leading = { ToolbarButton("Cancel") { dismiss() } }, actions = {
        ToolbarButton("Save", enabled = valid && !isSaving, bold = true) {
            isSaving = true
            app.scope.launch {
                try {
                    app.backend.saveOffer(offer)
                    onSaved()
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isSaving = false }
            }
        }
    }) {
        FormSection("Offer", footer = "Shown to artists, e.g. “Mixing half price” or “Weekday deal”.") {
            FormTextField("Title", offer.title, { offer = offer.copy(title = it.take(60)) })
            FormRow {
                T("Discount", Modifier.weight(1f), style = Type.body)
                Txt("${offer.percentOff}%", style = Type.body.bold)
                Stepper(offer.percentOff, 5..90) { offer = offer.copy(percentOff = it) }
            }
        }
        FormSection("Applies to") {
            FormPicker("Discount on", offer.appliesTo, TARGETS, { TARGET_TITLES.getValue(it) }) { offer = offer.copy(appliesTo = it, targetId = null) }
            if (offer.appliesTo == "session_type") {
                if (studio.sessionTypes.isEmpty()) FormContent { T("Add a session type first.", color = Theme.secondary) }
                else FormPicker("Session type", offer.targetId, studio.sessionTypes.map { it.id }, { id -> studio.sessionTypes.firstOrNull { it.id == id }?.name ?: tr("Choose…") }, translateOptions = false) {
                    offer = offer.copy(targetId = it)
                }
            } else if (offer.appliesTo == "add_on") {
                if (studio.addOns.isEmpty()) FormContent { T("Add extras to your prices first.", color = Theme.secondary) }
                else FormPicker("Extra", offer.targetId, studio.addOns.map { it.id }, { id -> studio.addOns.firstOrNull { it.id == id }?.name ?: tr("Choose…") }, translateOptions = false) {
                    offer = offer.copy(targetId = it)
                }
            }
        }
    }
    ErrorAlert(error) { error = null }
}

@Composable
private fun PromoCodeEditor(initial: PromoCode, onSaved: () -> Unit) {
    val app = LocalAppState.current
    val dismiss = LocalDismiss.current
    var code by remember { mutableStateOf(initial) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val valid = Regex("^[A-Z0-9]{3,20}$").matches(code.code)

    NavScreen(if (initial.uses < 0) "New promo code" else "Edit promo code", leading = { ToolbarButton("Cancel") { dismiss() } }, actions = {
        ToolbarButton("Save", enabled = valid && !isSaving, bold = true) {
            isSaving = true
            app.scope.launch {
                try {
                    app.backend.savePromoCode(code)
                    onSaved()
                    dismiss()
                } catch (e: Exception) { error = e.userMessage } finally { isSaving = false }
            }
        }
    }) {
        FormSection("Code", footer = "3–20 letters or digits, e.g. SUMMER20.") {
            FormRow {
                PlainTextField(code.code, { value -> code = code.copy(code = value.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }.take(20)) },
                    "SUMMER20", Modifier.weight(1f), capitalization = KeyboardCapitalization.Characters)
            }
            FormRow {
                T("Discount", Modifier.weight(1f), style = Type.body)
                Txt("${code.percentOff}%", style = Type.body.bold)
                Stepper(code.percentOff, 1..90) { code = code.copy(percentOff = it) }
            }
            FormTextField("Note for artists (optional)", code.description, { code = code.copy(description = it.take(200)) })
        }
        FormSection("Limits") {
            FormRow {
                T("Uses in total", Modifier.weight(1f), style = Type.body)
                Txt(code.maxUses?.toString() ?: tr("No limit"), style = Type.body.bold)
                Stepper(code.maxUses ?: 0, 0..1000) { code = code.copy(maxUses = it.takeIf { n -> n > 0 }) }
            }
            FormRow {
                T("Uses per artist", Modifier.weight(1f), style = Type.body)
                Txt("${code.maxUsesPerUser}", style = Type.body.bold)
                Stepper(code.maxUsesPerUser, 1..100) { code = code.copy(maxUsesPerUser = it) }
            }
        }
    }
    ErrorAlert(error) { error = null }
}
