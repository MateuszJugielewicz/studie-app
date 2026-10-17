package com.easysesh.app.ui.components

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.easysesh.app.ui.theme.EasyColors
import com.easysesh.app.ui.theme.LocalEasyColors

/**
 * Soft colour fields drawn with radial gradients: the aurora glow at the top of every screen.
 * Only drifts when `animated` is set (welcome, intro and sign-in screens).
 */
fun Modifier.auroraBackground(height: Dp = 380.dp, animated: Boolean = false, intensity: Float = 1f, paintBackground: Boolean = true): Modifier = composed {
    val colors = LocalEasyColors.current
    val reduce = LocalReduceEffects.current
    val drift = if (animated && !reduce) {
        val transition = rememberInfiniteTransition(label = "aurora")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(9000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "drift").value
    } else 0f
    drawBehind {
        if (paintBackground) drawRect(colors.background)
        drawAurora(colors, height.toPx().coerceAtMost(size.height), drift, intensity)
    }
}

private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

fun DrawScope.drawAurora(colors: EasyColors, height: Float, drift: Float, intensity: Float) {
    val w = size.width
    val h = height
    val alpha = (if (colors.isDark) 0.6f else 0.36f) * intensity
    fun blob(color: Color, diameter: Float, x: Float, y: Float, extra: Float = 1f) {
        val center = Offset(w / 2 + x, h / 2 + y)
        val radius = diameter / 2
        // Fade the glow out towards the bottom of the aurora band, like the iOS mask.
        drawCircle(
            Brush.radialGradient(
                listOf(color.copy(alpha = alpha * extra), color.copy(alpha = 0.35f * alpha * extra), color.copy(alpha = 0f)),
                center = center, radius = radius,
            ),
            radius = radius, center = center,
        )
    }
    blob(colors.accent, w * 1.5f, lerp(-w * 0.34f, -w * 0.12f, drift), lerp(-h * 0.24f, -h * 0.1f, drift))
    blob(colors.magenta, w * 1.25f, lerp(w * 0.38f, w * 0.18f, drift), lerp(-h * 0.12f, h * 0.04f, drift))
    blob(colors.violet, w * 1.4f, lerp(-w * 0.16f, w * 0.14f, drift), lerp(h * 0.28f, h * 0.16f, drift))
    blob(colors.cyan, w * 0.8f, lerp(-w * 0.42f, -w * 0.26f, drift), lerp(h * 0.24f, h * 0.34f, drift), 0.6f)
    // Blend into the page background below the band.
    drawRect(
        Brush.verticalGradient(listOf(Color.Transparent, colors.background), startY = h * 0.35f, endY = h * 1.05f),
        topLeft = Offset(0f, 0f), size = androidx.compose.ui.geometry.Size(w, h * 1.05f),
    )
}

/** Soft coloured glow behind a view (iOS `neonGlow`). */
fun Modifier.neonGlow(color: Color, radius: Dp = 14.dp, shape: Shape = RectangleShape, active: Boolean = true): Modifier =
    if (!active) this else shadow(radius * 0.8f, shape, clip = false, ambientColor = color.copy(alpha = 0.6f), spotColor = color.copy(alpha = 0.9f))

/** Tappable card that sinks slightly under the finger (iOS PressableCardStyle). */
fun Modifier.pressable(enabled: Boolean = true, haptic: Boolean = false, onClick: () -> Unit): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, spring(dampingRatio = 0.65f, stiffness = 600f), label = "press")
    val haptics = LocalHapticFeedback.current
    graphicsLayer { scaleX = scale; scaleY = scale }
        .clickable(interaction, indication = null, enabled = enabled) {
            if (haptic) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onClick()
        }
}

/** Cards lift in as they appear (iOS scrollReveal, simplified). */
@Composable
fun Modifier.scrollReveal(): Modifier = this

fun Modifier.scaleOnPress(pressed: Boolean): Modifier = scale(if (pressed) 0.97f else 1f)
