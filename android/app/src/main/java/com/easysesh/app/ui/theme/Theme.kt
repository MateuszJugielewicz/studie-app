package com.easysesh.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * EasySesh design tokens, the same as the iOS app: neutral surfaces, one signal colour (the "REC"
 * light) that glows into a neon gradient. Every colour adapts to light and dark mode.
 */
@Immutable
data class EasyColors(
    val isDark: Boolean,
    /** Signal red-orange, used sparingly: primary actions, selection, the logo dot. */
    val accent: Color,
    val magenta: Color,
    val violet: Color,
    val cyan: Color,
    /** Page background (iOS systemGroupedBackground). */
    val background: Color,
    /** Raised surfaces: cards, input fields, chat bubbles (iOS secondarySystemGroupedBackground). */
    val card: Color,
    /** Subtle fills: chips, placeholders (iOS tertiarySystemFill). */
    val fill: Color,
    /** Hairlines. */
    val stroke: Color,
    val positive: Color,
    val warning: Color,
    val red: Color,
    val blue: Color,
    /** Text colours (iOS label / secondaryLabel / tertiaryLabel). */
    val primary: Color,
    val secondary: Color,
    val tertiary: Color,
) {
    /** The "signal" gradient: selection, primary buttons, the logo dot. */
    val neon: Brush get() = Brush.horizontalGradient(listOf(accent, magenta, violet))
    val neonColors: List<Color> get() = listOf(accent, magenta, violet)
    /** Thin glass edge used on floating surfaces. */
    val glassEdge: Brush get() = Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.45f), Color.White.copy(alpha = 0.05f)))
    val onAccent: Color get() = Color.White
    val gray: Color get() = Color(0xFF8E8E93)
}

private fun c(hex: Long) = Color(0xFF000000 or hex)

val LightColors = EasyColors(
    isDark = false,
    accent = c(0xD9431E), magenta = c(0xE0246F), violet = c(0x6A4DF5), cyan = c(0x0FA5D6),
    background = c(0xF2F2F7), card = Color.White, fill = Color(0x1F767680), stroke = Color(0x14000000),
    positive = c(0x2F7D4F), warning = c(0xB86E00), red = c(0xFF3B30), blue = c(0x007AFF),
    primary = Color.Black, secondary = Color(0x993C3C43), tertiary = Color(0x4D3C3C43),
)

val DarkColors = EasyColors(
    isDark = true,
    accent = c(0xFF6A3D), magenta = c(0xFF3D8B), violet = c(0x8C73FF), cyan = c(0x3FD8FF),
    background = Color.Black, card = c(0x1C1C1E), fill = Color(0x3D767680), stroke = Color(0x14FFFFFF),
    positive = c(0x5CC98A), warning = c(0xF2A93B), red = c(0xFF453A), blue = c(0x0A84FF),
    primary = Color.White, secondary = Color(0x99EBEBF5), tertiary = Color(0x4DEBEBF5),
)

val LocalEasyColors = staticCompositionLocalOf { DarkColors }

/** Mirrors `Theme.accent` etc. from the iOS app. */
object Theme {
    val colors: EasyColors @Composable @ReadOnlyComposable get() = LocalEasyColors.current
    val accent: Color @Composable @ReadOnlyComposable get() = colors.accent
    val magenta: Color @Composable @ReadOnlyComposable get() = colors.magenta
    val violet: Color @Composable @ReadOnlyComposable get() = colors.violet
    val cyan: Color @Composable @ReadOnlyComposable get() = colors.cyan
    val background: Color @Composable @ReadOnlyComposable get() = colors.background
    val card: Color @Composable @ReadOnlyComposable get() = colors.card
    val fill: Color @Composable @ReadOnlyComposable get() = colors.fill
    val stroke: Color @Composable @ReadOnlyComposable get() = colors.stroke
    val positive: Color @Composable @ReadOnlyComposable get() = colors.positive
    val warning: Color @Composable @ReadOnlyComposable get() = colors.warning
    val red: Color @Composable @ReadOnlyComposable get() = colors.red
    val primary: Color @Composable @ReadOnlyComposable get() = colors.primary
    val secondary: Color @Composable @ReadOnlyComposable get() = colors.secondary
    val tertiary: Color @Composable @ReadOnlyComposable get() = colors.tertiary
    val neon: Brush @Composable @ReadOnlyComposable get() = colors.neon
    val onAccent: Color get() = Color.White

    val corner = 18.dp
    val spacing = 16.dp
}

/** Gradient pairs for icon tiles. */
object TilePalette {
    val signal: List<Color> @Composable @ReadOnlyComposable get() = listOf(Theme.accent, Theme.magenta)
    val violet: List<Color> @Composable @ReadOnlyComposable get() = listOf(Theme.magenta, Theme.violet)
    val ocean: List<Color> @Composable @ReadOnlyComposable get() = listOf(Theme.violet, Theme.cyan)
    val mint: List<Color> @Composable @ReadOnlyComposable get() = listOf(Theme.cyan, Theme.positive)
    val muted: List<Color> get() = listOf(Color.Gray.copy(alpha = 0.7f), Color.Gray.copy(alpha = 0.45f))
}

@Composable
fun EasySeshTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) DarkColors else LightColors
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.accent, onPrimary = Color.White, secondary = colors.magenta, tertiary = colors.violet,
            background = colors.background, onBackground = colors.primary, surface = colors.card, onSurface = colors.primary,
            surfaceVariant = colors.card, onSurfaceVariant = colors.secondary, surfaceContainer = colors.card,
            surfaceContainerHigh = colors.card, surfaceContainerHighest = c(0x2C2C2E), surfaceContainerLow = colors.card,
            outline = colors.secondary, outlineVariant = colors.stroke, error = colors.red,
        )
    } else {
        lightColorScheme(
            primary = colors.accent, onPrimary = Color.White, secondary = colors.magenta, tertiary = colors.violet,
            background = colors.background, onBackground = colors.primary, surface = colors.card, onSurface = colors.primary,
            surfaceVariant = c(0xF2F2F7), onSurfaceVariant = colors.secondary, surfaceContainer = Color.White,
            surfaceContainerHigh = Color.White, surfaceContainerHighest = c(0xE5E5EA), surfaceContainerLow = Color.White,
            outline = colors.secondary, outlineVariant = colors.stroke, error = colors.red,
        )
    }
    CompositionLocalProvider(LocalEasyColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
