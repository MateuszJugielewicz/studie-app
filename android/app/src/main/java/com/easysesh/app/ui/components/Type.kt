package com.easysesh.app.ui.components

import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.easysesh.app.core.tr
import com.easysesh.app.ui.theme.Theme

/** iOS Dynamic Type sizes (default content size). */
object Type {
    val largeTitle = TextStyle(fontSize = 34.sp, lineHeight = 41.sp)
    val title = TextStyle(fontSize = 28.sp, lineHeight = 34.sp)
    val title2 = TextStyle(fontSize = 22.sp, lineHeight = 28.sp)
    val title3 = TextStyle(fontSize = 20.sp, lineHeight = 25.sp)
    val headline = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val callout = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)
    val caption2 = TextStyle(fontSize = 11.sp, lineHeight = 13.sp)

    fun system(size: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(fontSize = size.sp, fontWeight = weight)
    /** Large editorial headline. */
    fun display(size: Int) = TextStyle(fontSize = size.sp, lineHeight = (size * 1.08).sp, fontWeight = FontWeight.Bold)
}

fun TextStyle.weight(weight: FontWeight) = copy(fontWeight = weight)
val TextStyle.semibold get() = copy(fontWeight = FontWeight.SemiBold)
val TextStyle.bold get() = copy(fontWeight = FontWeight.Bold)
val TextStyle.heavy get() = copy(fontWeight = FontWeight.ExtraBold)
fun TextStyle.tracking(points: Float) = copy(letterSpacing = (points / (fontSize.value.coerceAtLeast(1f))).em)

/** Translated text (iOS `Text("…")` / `Text(localized:)`). */
@Composable
fun T(
    key: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    color: Color = Color.Unspecified,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) = Txt(tr(key), modifier, style, color, align, maxLines)

/** Plain, untranslated text (names, amounts, user content). */
@Composable
fun Txt(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    color: Color = Color.Unspecified,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    val resolved = if (color == Color.Unspecified && style.color == Color.Unspecified) Theme.primary else color
    Text(text, modifier, color = resolved, style = style, textAlign = align, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

/** Text painted with a gradient (iOS foregroundStyle(gradient)). */
@Composable
fun GradientText(text: String, brush: Brush, style: TextStyle, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Text(text, modifier, style = style.copy(brush = brush), maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

/** Small uppercase label above a section or value. */
@Composable
fun Eyebrow(text: String, modifier: Modifier = Modifier) {
    Txt(tr(text).uppercase(L10nLocale()), modifier, style = Type.caption.semibold.copy(letterSpacing = 0.07.em), color = Theme.secondary)
}

@Composable
private fun L10nLocale() = com.easysesh.app.core.L10n.locale()

val TextUnitZero: TextUnit = 0.sp
