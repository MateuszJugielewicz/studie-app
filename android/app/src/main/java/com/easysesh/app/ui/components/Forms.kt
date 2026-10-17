package com.easysesh.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.tr
import com.easysesh.app.ui.theme.Theme

/*
 * iOS Form / List with sections, in the EasySesh house style (frosted rows over the aurora).
 * Screens use NavScreen { FormSection(...) { FormRow ... } }.
 */

@Composable
fun FormSection(
    header: String? = null,
    footer: String? = null,
    translate: Boolean = true,
    footerColor: Color? = null,
    headerContent: (@Composable () -> Unit)? = null,
    footerContent: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when {
            headerContent != null -> Box(Modifier.padding(horizontal = 16.dp)) { headerContent() }
            header != null -> Txt((if (translate) tr(header) else header).uppercase(), Modifier.padding(horizontal = 16.dp), style = Type.footnote, color = Theme.secondary)
        }
        val shape = RoundedCornerShape(12.dp)
        Column(
            Modifier.fillMaxWidth().clip(shape).background(Theme.card.copy(alpha = 0.82f), shape)
                .border(0.6.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.3f), Theme.primary.copy(alpha = 0.05f))), shape),
        ) {
            content()
        }
        when {
            footerContent != null -> Box(Modifier.padding(horizontal = 16.dp)) { footerContent() }
            footer != null -> Txt(if (translate) tr(footer) else footer, Modifier.padding(horizontal = 16.dp), style = Type.footnote, color = footerColor ?: Theme.secondary)
        }
    }
}

/** A row in a form section; draws the separator above every row but the first. */
@Composable
fun FormRow(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) {
    Column {
        Row(
            modifier.fillMaxWidth().heightIn(min = 46.dp)
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
        Box(Modifier.fillMaxWidth().padding(start = 16.dp).heightIn(max = 0.5.dp).background(Theme.stroke))
    }
}

/** Row with a title and a chevron that pushes `destination` (iOS NavigationLink in a Form). */
@Composable
fun FormNavRow(title: String, symbol: String? = null, value: String? = null, translate: Boolean = true, tint: Color = Theme.primary, iconColors: List<Color>? = null, destination: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    FormRow(onClick = { navigator?.push(destination) }) {
        RowLabel(title, symbol, translate, tint, iconColors)
        if (value != null) Txt(value, style = Type.body, color = Theme.secondary, maxLines = 1)
        Sym("chevron.right", size = 18.dp, tint = Theme.tertiary)
    }
}

@Composable
fun RowScope.RowLabel(title: String, symbol: String? = null, translate: Boolean = true, tint: Color = Theme.primary, iconColors: List<Color>? = null) {
    if (symbol != null) {
        if (iconColors != null) IconTile(symbol, 30.dp, iconColors) else Sym(symbol, size = 20.dp, tint = if (tint == Theme.primary) Theme.accent else tint)
    }
    Txt(if (translate) tr(title) else title, Modifier.weight(1f), style = Type.body, color = tint)
}

/** Tappable action row (iOS Button inside a Form). */
@Composable
fun FormButton(title: String, symbol: String? = null, color: Color = Theme.accent, enabled: Boolean = true, translate: Boolean = true, iconColors: List<Color>? = null, onClick: () -> Unit) {
    FormRow(onClick = if (enabled) onClick else null) {
        val tint = if (enabled) color else Theme.secondary
        if (symbol != null) {
            if (iconColors != null) IconTile(symbol, 30.dp, iconColors) else Sym(symbol, size = 20.dp, tint = tint)
        }
        Txt(if (translate) tr(title) else title, Modifier.weight(1f), style = Type.body, color = tint)
    }
}

@Composable
fun FormToggle(title: String, checked: Boolean, symbol: String? = null, enabled: Boolean = true, translate: Boolean = true, iconColors: List<Color>? = null, onChange: (Boolean) -> Unit) {
    FormRow {
        RowLabel(title, symbol, translate, if (enabled) Theme.primary else Theme.secondary, iconColors)
        Switch(
            checked, onChange, enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = Theme.positive, checkedThumbColor = Color.White, uncheckedTrackColor = Theme.fill, uncheckedBorderColor = Color.Transparent, uncheckedThumbColor = Color.White),
        )
    }
}

/** Text field row (iOS TextField in a Form). */
@Composable
fun FormTextField(
    placeholder: String,
    value: String,
    onChange: (String) -> Unit,
    keyboard: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    secure: Boolean = false,
    minLines: Int = 1,
    maxLines: Int = 1,
    style: TextStyle = Type.body,
    label: String? = null,
) {
    FormRow {
        if (label != null) T(label, style = Type.body)
        PlainTextField(value, onChange, placeholder, Modifier.weight(1f), keyboard, capitalization, secure, minLines, maxLines, style)
    }
}

/** Borderless text field with a translated placeholder. */
@Composable
fun PlainTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboard: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    secure: Boolean = false,
    minLines: Int = 1,
    maxLines: Int = 1,
    style: TextStyle = Type.body,
) {
    BasicTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier,
        textStyle = style.copy(color = Theme.primary),
        cursorBrush = SolidColor(Theme.accent),
        singleLine = maxLines == 1,
        minLines = minLines,
        maxLines = maxLines,
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(capitalization = capitalization, keyboardType = keyboard, autoCorrectEnabled = !secure && keyboard == KeyboardType.Text),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Txt(tr(placeholder), style = style, color = Theme.tertiary)
                inner()
            }
        },
    )
}

/** A picker row: shows the selected value and opens a menu (iOS Picker in a Form). */
@Composable
fun <T> FormPicker(title: String, selection: T, options: List<T>, label: (T) -> String, translateOptions: Boolean = true, symbol: String? = null, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    FormRow(onClick = { open = true }) {
        RowLabel(title, symbol)
        Box {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Txt(if (translateOptions) tr(label(selection)) else label(selection), style = Type.body, color = Theme.secondary, maxLines = 1)
                Sym("arrow.up.arrow.down", size = 14.dp, tint = Theme.tertiary)
            }
            DropdownMenu(open, onDismissRequest = { open = false }, containerColor = Theme.card) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Txt(if (translateOptions) tr(label(option)) else label(option), style = Type.body) },
                        trailingIcon = if (option == selection) ({ Sym("checkmark", tint = Theme.accent) }) else null,
                        onClick = { open = false; onSelect(option) },
                    )
                }
            }
        }
    }
}

/** Inline list of options with a check mark (iOS Picker with .inline style). */
@Composable
fun <T> FormInlinePicker(selection: T, options: List<T>, label: (T) -> String, symbol: ((T) -> String)? = null, onSelect: (T) -> Unit) {
    options.forEach { option ->
        FormRow(onClick = { onSelect(option) }) {
            if (symbol != null) Sym(symbol(option), size = 20.dp, tint = Theme.accent)
            T(label(option), Modifier.weight(1f), style = Type.body)
            if (option == selection) Sym("checkmark", tint = Theme.accent)
        }
    }
}

@Composable
fun FormStepper(title: String, value: Int, range: IntRange, translate: Boolean = true, onChange: (Int) -> Unit) {
    FormRow {
        Txt(if (translate) tr(title) else title, Modifier.weight(1f), style = Type.body)
        Stepper(value, range, onChange)
    }
}

@Composable
fun Stepper(value: Int, range: IntRange, onChange: (Int) -> Unit) {
    val shape = RoundedCornerShape(9.dp)
    Row(Modifier.clip(shape).background(Theme.fill, shape), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(46.dp, 32.dp).clickable(enabled = value > range.first) { onChange(value - 1) }, contentAlignment = Alignment.Center) {
            Txt("−", style = Type.title3, color = if (value > range.first) Theme.primary else Theme.tertiary)
        }
        Box(Modifier.size(0.5.dp, 18.dp).background(Theme.stroke))
        Box(Modifier.size(46.dp, 32.dp).clickable(enabled = value < range.last) { onChange(value + 1) }, contentAlignment = Alignment.Center) {
            Txt("+", style = Type.title3, color = if (value < range.last) Theme.primary else Theme.tertiary)
        }
    }
}

@Composable
fun FormSlider(value: Float, range: ClosedFloatingPointRange<Float>, steps: Int = 0, onChange: (Float) -> Unit) {
    FormRow {
        Slider(value, onChange, Modifier.weight(1f), valueRange = range, steps = steps,
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Theme.accent, inactiveTrackColor = Theme.fill, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent))
    }
}

/** A plain content row (iOS arbitrary view inside a Form section). */
@Composable
fun FormContent(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}
