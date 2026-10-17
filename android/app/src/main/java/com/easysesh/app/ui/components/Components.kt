package com.easysesh.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.easysesh.app.core.Money
import com.easysesh.app.core.tr
import com.easysesh.app.model.BookingStatus
import com.easysesh.app.model.StudioStatus
import com.easysesh.app.ui.theme.Symbols
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import java.time.LocalTime
import java.util.Locale

// MARK: Icons

@Composable
fun Sym(name: String, modifier: Modifier = Modifier, size: Dp = 18.dp, tint: Color = Theme.primary) {
    Icon(Symbols[name], contentDescription = null, modifier = modifier.size(size), tint = tint)
}

/** Rounded gradient square holding an icon. */
@Composable
fun IconTile(symbol: String, size: Dp = 36.dp, colors: List<Color> = TilePalette.signal, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(size * 0.3f)
    Box(
        modifier
            .size(size)
            .background(Brush.linearGradient(colors), shape)
            .border(0.6.dp, Color.White.copy(alpha = 0.25f), shape),
        contentAlignment = Alignment.Center,
    ) { Sym(symbol, size = size * 0.5f, tint = Color.White) }
}

/** Round frosted icon, used for header actions. */
@Composable
fun GlassIcon(symbol: String, modifier: Modifier = Modifier, tint: Color = Theme.primary) {
    Box(
        modifier
            .size(40.dp)
            .background(Theme.card.copy(alpha = 0.72f), CircleShape)
            .border(0.8.dp, Theme.colors.glassEdge, CircleShape),
        contentAlignment = Alignment.Center,
    ) { Sym(symbol, size = 19.dp, tint = tint) }
}

@Composable
fun GlassIconButton(symbol: String, label: String, onClick: () -> Unit) {
    GlassIcon(symbol, Modifier.pressable(onClick = onClick))
}

// MARK: Logo

/** Lowercase wordmark with a small "recording" dot. */
@Composable
fun EasySeshLogo(size: Int = 28, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy((size * 0.12).dp)) {
        Txt("easysesh", style = Type.system(size, FontWeight.ExtraBold).tracking(-size * 0.03f))
        Box(
            Modifier
                .padding(bottom = (size * 0.18).dp)
                .size((size * 0.26).dp)
                .neonGlow(Theme.accent, (size * 0.25).dp, CircleShape)
                .background(Theme.neon, CircleShape),
        )
    }
}

// MARK: Surfaces

/** Frosted card with a light glass edge. Looks best over the aurora background. */
fun Modifier.glassCard(padding: Dp = 16.dp, cornerRadius: Dp = 22.dp): Modifier = this.then(GlassCardModifier(padding, cornerRadius))

private data class GlassCardModifier(val padding: Dp, val cornerRadius: Dp) : Modifier.Element

@Composable
fun Modifier.glass(padding: Dp = 16.dp, cornerRadius: Dp = 22.dp): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    return this
        .background(Theme.card.copy(alpha = 0.78f), shape)
        .border(0.8.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.4f), Theme.primary.copy(alpha = 0.06f))), shape)
        .clip(shape)
        .padding(padding)
}

/** Card container (iOS `.card()` / `.glassCard()`). */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    padding: Dp = 16.dp,
    cornerRadius: Dp = 22.dp,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val base = if (onClick != null) modifier.pressable(onClick = onClick) else modifier
    Column(base.fillMaxWidth().glass(padding, cornerRadius), content = content)
}

// MARK: Buttons

@Composable
fun PrimaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, symbol: String? = null, translate: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .neonGlow(Theme.magenta, 16.dp, shape, enabled)
            .clip(shape)
            .background(if (enabled) Theme.neon else Brush.linearGradient(listOf(Theme.fill, Theme.fill)))
            .background(if (enabled) Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.22f), Color.Transparent)) else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)))
            .border(0.8.dp, Color.White.copy(alpha = if (enabled) 0.2f else 0f), shape)
            .pressable(enabled = enabled, haptic = true, onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        ButtonLabel(if (translate) tr(title) else title, symbol, if (enabled) Color.White else Theme.secondary)
    }
}

@Composable
fun SecondaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, symbol: String? = null, color: Color = Theme.primary, translate: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .clip(shape)
            .background(Theme.card.copy(alpha = 0.6f))
            .border(1.dp, Theme.primary.copy(alpha = 0.14f), shape)
            .pressable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.5f)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) { ButtonLabel(if (translate) tr(title) else title, symbol, color) }
}

@Composable
private fun ButtonLabel(text: String, symbol: String?, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (symbol != null) Sym(symbol, size = 18.dp, tint = color)
        Txt(text, style = Type.body.semibold, color = color, align = TextAlign.Center)
    }
}

/** Plain text button (iOS borderless Button). */
@Composable
fun LinkButton(title: String, modifier: Modifier = Modifier, color: Color = Theme.accent, style: androidx.compose.ui.text.TextStyle = Type.subheadline.semibold, enabled: Boolean = true, onClick: () -> Unit) {
    Txt(tr(title), modifier.clip(RoundedCornerShape(8.dp)).clickable(enabled = enabled, onClick = onClick).padding(vertical = 6.dp, horizontal = 4.dp),
        style = style, color = if (enabled) color else Theme.secondary)
}

// MARK: Badges & tags

/** Cosmetic "EasySesh team" badge. It shows who works at EasySesh; it grants no rights in the app. */
@Composable
fun AdminBadge(compact: Boolean = false) {
    Row(
        Modifier
            .neonGlow(Theme.magenta, 5.dp, CircleShape)
            .background(Theme.neon, CircleShape)
            .border(0.6.dp, Color.White.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = if (compact) 5.dp else 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Sym("sparkle", size = if (compact) 9.dp else 10.dp, tint = Color.White)
        if (!compact) Txt("TEAM", style = Type.system(9, FontWeight.ExtraBold).tracking(0.8f), color = Color.White)
    }
}

/** Special tag only admins can add to a studio, e.g. "Staff pick". */
@Composable
fun SpecialTagChip(title: String) {
    Row(
        Modifier
            .background(Theme.magenta.copy(alpha = 0.12f), CircleShape)
            .border(1.dp, Theme.neon, CircleShape)
            .padding(horizontal = 9.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Sym("star.fill", size = 10.dp, tint = Theme.magenta)
        GradientText(tr(title), Theme.neon, Type.caption.bold)
    }
}

/** Marks a studio that paid to be promoted. */
@Composable
fun PromotedTag() {
    Row(
        Modifier
            .neonGlow(Theme.magenta, 6.dp, CircleShape)
            .background(Theme.neon, CircleShape)
            .border(0.6.dp, Color.White.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 9.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Sym("megaphone.fill", size = 10.dp, tint = Color.White)
        Txt(tr("Promoted").uppercase(), style = Type.caption2.heavy.tracking(0.6f), color = Color.White)
    }
}

/** Stars + average, e.g. for an artist's rating from studios. */
@Composable
fun RatingPill(average: Double, count: Int) {
    Row(
        Modifier.background(Theme.card.copy(alpha = 0.78f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Sym("star.fill", size = 15.dp, tint = Theme.magenta)
        Txt(if (count == 0) "–" else String.format(Locale.getDefault(), "%.1f", average), style = Type.subheadline.heavy)
        Txt("($count)", style = Type.subheadline, color = Theme.secondary)
    }
}

@Composable
fun RatingLabel(rating: Double, count: Int, compact: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Sym("star.fill", size = 13.dp)
        if (count == 0) T("New", style = Type.subheadline.semibold)
        else {
            Txt(String.format(Locale.getDefault(), "%.1f", rating), style = Type.subheadline.semibold)
            if (!compact) Txt("($count)", style = Type.subheadline, color = Theme.secondary)
        }
    }
}

@Composable
fun StarRow(rating: Int, size: Dp = 12.dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (index in 1..5) {
            Sym(if (index <= rating) "star.fill" else "star", size = size + 2.dp, tint = if (index <= rating) Theme.primary else Theme.secondary.copy(alpha = 0.5f))
        }
    }
}

@Composable
fun StarPicker(title: String, rating: Int, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        T(title, Modifier.weight(1f), style = Type.body)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (index in 1..5) {
                Sym(if (index <= rating) "star.fill" else "star", Modifier.clickable { onChange(index) }, size = 24.dp,
                    tint = if (index <= rating) Theme.accent else Theme.secondary.copy(alpha = 0.5f))
            }
        }
    }
}

@Composable
fun VerifiedBadge() = Sym("checkmark.seal.fill", size = 16.dp, tint = Theme.colors.blue)

@Composable
fun StatusPill(text: String, color: Color) {
    Txt(
        tr(text),
        Modifier
            .background(color.copy(alpha = 0.14f), CircleShape)
            .border(0.8.dp, color.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp),
        style = Type.caption.semibold, color = color,
    )
}

val BookingStatus.color: Color
    @Composable get() = when (this) {
        BookingStatus.AwaitingPayment, BookingStatus.PendingApproval -> Theme.warning
        BookingStatus.Confirmed -> Theme.positive
        BookingStatus.Completed -> Theme.secondary
        BookingStatus.Declined, BookingStatus.Cancelled, BookingStatus.Expired -> Theme.colors.gray
        BookingStatus.Disputed -> Theme.red
    }

val StudioStatus.color: Color
    @Composable get() = when (this) {
        StudioStatus.Draft -> Theme.colors.gray
        StudioStatus.PendingReview, StudioStatus.ChangesRequested -> Theme.warning
        StudioStatus.Approved -> Theme.positive
        StudioStatus.Rejected, StudioStatus.Suspended -> Theme.red
    }

// MARK: Images

@Composable
fun RemoteImage(url: String?, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop) {
    if (url.isNullOrEmpty()) {
        ImagePlaceholder(modifier)
    } else {
        SubcomposeAsyncImage(
            model = url,
            contentDescription = null,
            modifier = modifier,
            contentScale = contentScale,
            loading = { ImagePlaceholder(Modifier.fillMaxSize(), loading = true) },
            error = { ImagePlaceholder(Modifier.fillMaxSize()) },
        )
    }
}

@Composable
private fun ImagePlaceholder(modifier: Modifier, loading: Boolean = false) {
    Box(modifier.background(Theme.fill), contentAlignment = Alignment.Center) {
        if (loading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = Theme.secondary)
        else Sym("photo", size = 26.dp, tint = Theme.tertiary)
    }
}

@Composable
fun Avatar(url: String?, name: String, size: Dp = 44.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).clip(CircleShape).background(Theme.fill), contentAlignment = Alignment.Center) {
        if (url != null) RemoteImage(url, Modifier.fillMaxSize())
        else {
            val initials = name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first() }.joinToString("").uppercase()
            Txt(initials, style = Type.system((size.value * 0.36f).toInt(), FontWeight.SemiBold))
        }
    }
}

// MARK: Chips

@Composable
fun Chip(title: String, symbol: String? = null, isSelected: Boolean = false, translate: Boolean = true, modifier: Modifier = Modifier) {
    val shape = CircleShape
    Row(
        modifier
            .then(if (isSelected) Modifier.neonGlow(Theme.magenta, 8.dp, shape) else Modifier)
            .clip(shape)
            .background(if (isSelected) Theme.neon else Brush.linearGradient(listOf(Theme.card.copy(alpha = 0.6f), Theme.card.copy(alpha = 0.6f))))
            .border(1.dp, if (isSelected) Color.White.copy(alpha = 0.25f) else Theme.primary.copy(alpha = 0.12f), shape)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val color = if (isSelected) Color.White else Theme.primary
        if (symbol != null) Sym(symbol, size = 15.dp, tint = color)
        Txt(if (translate) tr(title) else title, style = Type.subheadline.copy(fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal), color = color)
    }
}

/** Multi-select chip picker. */
@Composable
fun <T> ChipPicker(items: List<T>, selection: Set<T>, title: (T) -> String, symbol: ((T) -> String)? = null, onChange: (Set<T>) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            Chip(title(item), symbol?.invoke(item), item in selection,
                modifier = Modifier.clickable { onChange(if (item in selection) selection - item else selection + item) })
        }
    }
}

/** Wrapping horizontal layout for chips. */
@Composable
fun FlowLayout(spacing: Dp = 8.dp, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(spacing)) { content() }
}

// MARK: Rows & headers

@Composable
fun SectionHeader(title: String, actionTitle: String? = null, action: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        T(title, Modifier.weight(1f), style = Type.title3.bold)
        if (actionTitle != null && action != null) LinkButton(actionTitle, onClick = action)
    }
}

/** Section title with an optional count bubble. */
@Composable
fun GlowSectionHeader(title: String, count: Int? = null) {
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        T(title, style = Type.title3.bold)
        if (count != null && count > 0) {
            Txt(
                "$count",
                Modifier.neonGlow(Theme.magenta, 6.dp, CircleShape).background(Theme.neon, CircleShape).padding(horizontal = 8.dp, vertical = 2.dp),
                style = Type.caption.bold, color = Color.White,
            )
        }
    }
}

@Composable
fun InfoRow(symbol: String, title: String, value: String? = null, translateTitle: Boolean = true) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) { Sym(symbol, tint = Theme.secondary) }
        Txt(if (translateTitle) tr(title) else title, Modifier.weight(1f), style = Type.body)
        if (value != null) Txt(value, style = Type.body, color = Theme.secondary, align = TextAlign.End)
    }
}

@Composable
fun PriceRow(title: String, amount: Int, currency: String, emphasized: Boolean = false) {
    val style = if (emphasized) Type.headline else Type.body
    val color = if (emphasized) Theme.primary else Theme.secondary
    Row(Modifier.fillMaxWidth()) {
        T(title, Modifier.weight(1f), style = style, color = color)
        Txt(Money.format(amount, currency), style = style, color = color)
    }
}

/** Soft empty state that sits on a glass card. */
@Composable
fun GlassEmptyState(title: String, symbol: String, message: String? = null) {
    GlassCard(padding = 20.dp) {
        Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile(symbol, 48.dp, TilePalette.violet)
            T(title, style = Type.headline, align = TextAlign.Center)
            if (message != null) T(message, style = Type.subheadline, color = Theme.secondary, align = TextAlign.Center)
        }
    }
}

/** "On air" dot with an expanding ring. */
@Composable
fun PulseDot(color: Color = Theme.positive, isActive: Boolean = true) {
    val reduce = LocalReduceEffects.current
    val transition = rememberInfiniteTransition(label = "pulse")
    val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1500)), label = "t")
    Box(Modifier.size(10.dp), contentAlignment = Alignment.Center) {
        if (isActive && !reduce) {
            Box(
                Modifier.size(10.dp)
                    .graphicsLayer { scaleX = 0.8f + t * 1.4f; scaleY = 0.8f + t * 1.4f; alpha = 0.9f * (1 - t) }
                    .background(color.copy(alpha = 0.4f), CircleShape),
            )
        }
        Box(Modifier.size(10.dp).background(if (isActive) color else Theme.secondary, CircleShape))
    }
}

/** "Good morning" / "Good afternoon" / "Good evening". */
fun greeting(): String = when (LocalTime.now().hour) {
    in 5..11 -> "Good morning"
    in 12..17 -> "Good afternoon"
    else -> "Good evening"
}

// MARK: Alerts

/** Presents an error as an alert (iOS `.errorAlert`). Empty messages (cancelled requests) aren't shown. */
@Composable
fun ErrorAlert(error: String?, onDismiss: () -> Unit) {
    if (error.isNullOrEmpty()) return
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { T("OK", color = Theme.accent) } },
        title = { T("Something went wrong", style = Type.headline) },
        text = { Txt(error, style = Type.body, color = Theme.secondary) },
        containerColor = Theme.card,
    )
}

/** Simple alert with an OK button (iOS `.alert(title, message)`). */
@Composable
fun InfoAlert(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { T("OK", color = Theme.accent) } },
        title = { T(title, style = Type.headline) },
        text = { Txt(message, style = Type.body, color = Theme.secondary) },
        containerColor = Theme.card,
    )
}

@Composable
fun Divider(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(0.5.dp).background(Theme.stroke))

@Composable
fun VSpace(height: Dp) = Spacer(Modifier.height(height))

@Composable
fun HSpace(width: Dp) = Spacer(Modifier.width(width))

@Composable
fun RowScope.Fill() = Spacer(Modifier.weight(1f))

@Composable
fun ColumnScope.FillV() = Spacer(Modifier.weight(1f))

@Composable
fun ProgressSpinner(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = Theme.accent, strokeWidth = 3.dp, modifier = Modifier.size(28.dp))
    }
}
