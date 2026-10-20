package com.easysesh.app.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.easysesh.app.AppTab
import com.easysesh.app.core.L10n
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette

/** A spotlight walkthrough of the tab bar (e.g. right after a studio is approved). */
data class TabTour(val steps: List<TourStep>, val onFinish: () -> Unit) {
    companion object {
        /** Shown once when a studio is approved. */
        fun studioApproved(onFinish: () -> Unit) = TabTour(listOf(
            TourStep(null, "party.popper.fill", "You're live on EasySesh!",
                "Your studio was approved and artists can now book you. Here's a 30-second tour of where everything is."),
            TourStep(AppTab.Dashboard, "square.grid.2x2.fill", "Dashboard",
                "Earnings, booking requests and upcoming sessions at a glance. Go live or pause your studio here."),
            TourStep(AppTab.Calendar, "calendar", "Calendar",
                "Every session by day. Block time when the studio is busy so nobody can book it."),
            TourStep(AppTab.Messages, "bubble.left.and.bubble.right.fill", "Messages",
                "Chat with artists about their bookings, or write to an artist first with the + button."),
            TourStep(AppTab.Notifications, "bell.badge.fill", "Inbox",
                "Booking requests, reviews and payouts land here and as push notifications."),
            TourStep(AppTab.Profile, "building.2.fill", "Your studio",
                "Edit your listing, prices and opening hours, set up payouts and change app settings."),
        ), onFinish)
    }
}

/** `tab == null` shows a centred welcome card without a spotlight. */
data class TourStep(val tab: AppTab?, val symbol: String, val title: String, val message: String)

@Composable
fun TourOverlay(tour: TabTour, frames: Map<AppTab, Rect>, onSelect: (AppTab) -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    val step = tour.steps[index]
    val isLast = index == tour.steps.lastIndex
    val density = LocalDensity.current
    val pulse by rememberInfiniteTransition(label = "tour").animateFloat(0f, 1f, infiniteRepeatable(tween(1200)), label = "pulse")
    val reduce = LocalReduceEffects.current

    fun finish() {
        tour.steps.firstNotNullOfOrNull { it.tab }?.let(onSelect)
        tour.onFinish()
    }
    fun advance() {
        if (isLast) return finish()
        index += 1
        tour.steps[index].tab?.let(onSelect)
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val target = step.tab?.let { frames[it] }?.inflate(with(density) { 5.dp.toPx() })
        val corner = with(density) { 28.dp.toPx() }
        Canvas(
            Modifier.fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .clickable(remember { MutableInteractionSource() }, indication = null) { advance() },
        ) {
            drawRect(Color.Black.copy(alpha = 0.66f))
            if (target != null) {
                drawRoundRect(Color.Transparent, target.topLeft, target.size, CornerRadius(corner), blendMode = BlendMode.Clear)
                val grow = if (reduce) 0f else pulse * 0.1f
                val w = target.width * (1 + grow)
                val h = target.height * (1 + grow)
                drawRoundRect(Color(0xFFFF3D8B).copy(alpha = 1 - pulse * 0.6f), Offset(target.center.x - w / 2, target.center.y - h / 2), Size(w, h), CornerRadius(corner), style = Stroke(width = 2.5.dp.toPx()))
            }
        }
        val bottomPadding = if (target != null) with(density) { (constraints.maxHeight - target.top).toDp() + 18.dp } else maxHeight * 0.3f
        Box(Modifier.fillMaxSize().padding(start = 20.dp, end = 20.dp, bottom = bottomPadding.coerceAtLeast(0.dp)), contentAlignment = Alignment.BottomCenter) {
            AnimatedContent(index, transitionSpec = { (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut()) }, label = "tour") { i ->
                val s = tour.steps[i]
                Column(
                    Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(26.dp)).border(0.8.dp, Theme.colors.glassEdge, RoundedCornerShape(26.dp)).padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconTile(s.symbol, if (s.tab == null) 52.dp else 42.dp, TilePalette.signal)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Eyebrow(L10n.format("Step %lld of %lld", i + 1, tour.steps.size))
                            T(s.title, style = Type.title3.heavy)
                        }
                    }
                    T(s.message, style = Type.subheadline, color = Theme.secondary)
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            tour.steps.indices.forEach { dot ->
                                Box(Modifier.size(if (dot == i) 16.dp else 6.dp, 6.dp).background(if (dot == i) Theme.accent else Theme.secondary.copy(alpha = 0.4f), CircleShape))
                            }
                        }
                        Fill()
                        if (i != tour.steps.lastIndex) LinkButton("Skip", color = Theme.secondary) { finish() }
                        HSpace(6.dp)
                        Txt(
                            com.easysesh.app.core.tr(if (i == tour.steps.lastIndex) "Let's go" else "Next"),
                            Modifier.neonGlow(Theme.magenta, 10.dp, CircleShape).background(Theme.neon, CircleShape)
                                .pressable { advance() }.padding(horizontal = 18.dp, vertical = 10.dp),
                            style = Type.subheadline.bold, color = Color.White,
                        )
                    }
                }
            }
        }
    }
}
