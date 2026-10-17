package com.easysesh.app.ui.features

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.easysesh.app.services.AppLanguage
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import kotlinx.coroutines.launch

private data class IntroFeature(val symbol: String, val colors: List<Color>, val title: String, val message: String)

/** First launch: pick a language, then a short tour of what the app does. */
@Composable
fun IntroView() {
    val app = LocalAppState.current
    val preferences = app.preferences
    val features = listOf(
        IntroFeature("sparkle.magnifyingglass", TilePalette.signal, "Find your sound", "Discover recording studios near you with real prices, gear lists and open slots."),
        IntroFeature("calendar.badge.checkmark", TilePalette.violet, "Book in seconds", "Pick a time, pay securely in the app or in cash at the studio, and get instant confirmation."),
        IntroFeature("bubble.left.and.bubble.right.fill", TilePalette.ocean, "Talk to the studio", "Chat about your session, share references and get reminders before you go."),
        IntroFeature("music.mic", TilePalette.mint, "Run a studio?", "List your rooms, fill your calendar and get paid. Every studio is reviewed before it goes live."),
    )
    val pageCount = features.size + 1
    val pager = rememberPagerState { pageCount }
    val scope = rememberCoroutineScope()
    val isLast = pager.currentPage == pageCount - 1
    fun finish() = preferences.updateHasSeenIntro(true)

    Column(Modifier.fillMaxSize().auroraBackground(700.dp, animated = true).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 24.dp).padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            EasySeshLogo(24)
            Fill()
            if (pager.currentPage > 0 && !isLast) LinkButton("Skip", color = Theme.secondary) { finish() }
        }
        HorizontalPager(pager, Modifier.weight(1f)) { page ->
            if (page == 0) LanguagePage() else IntroFeaturePage(features[page - 1], pager.currentPage == page)
        }
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            PageDots(pageCount, pager.currentPage)
            PrimaryButton(if (isLast) "Get started" else "Continue") {
                if (isLast) finish() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
            }
        }
    }
}

@Composable
private fun LanguagePage() {
    val preferences = LocalAppState.current.preferences
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(Modifier.padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            T("Welcome to EasySesh", style = Type.system(36, FontWeight.ExtraBold).tracking(-0.8f))
            T("Choose your language. You can change it any time in Settings.", style = Type.body, color = Theme.secondary)
        }
        AppLanguage.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { language ->
                    LanguageCard(language, preferences.language == language, Modifier.weight(1f)) { preferences.updateLanguage(language) }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun LanguageCard(language: AppLanguage, isSelected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier
            .height(56.dp)
            .then(if (isSelected) Modifier.neonGlow(Theme.magenta, 12.dp, shape) else Modifier)
            .background(if (isSelected) Theme.neon else Brush.linearGradient(listOf(Theme.card.copy(alpha = 0.6f), Theme.card.copy(alpha = 0.6f))), shape)
            .border(1.dp, if (isSelected) Color.Transparent else Theme.primary.copy(alpha = 0.1f), shape)
            .pressable(onClick = onClick)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Txt(language.flag, style = Type.title2)
        Txt(language.nativeName, Modifier.weight(1f), style = Type.subheadline.semibold, color = if (isSelected) Color.White else Theme.primary, maxLines = 1)
        if (isSelected) Sym("checkmark.circle.fill", tint = Color.White)
    }
}

@Composable
private fun IntroFeaturePage(feature: IntroFeature, isCurrent: Boolean) {
    val appear = remember { Animatable(0f) }
    LaunchedEffect(isCurrent) {
        if (isCurrent) { appear.snapTo(0f); appear.animateTo(1f, spring(dampingRatio = 0.7f, stiffness = 120f)) }
    }
    val reduce = LocalReduceEffects.current
    val rotation by rememberInfiniteTransition(label = "ring").animateFloat(0f, 360f, infiniteRepeatable(tween(18000, easing = LinearEasing)), label = "r")
    val a = appear.value
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp, Alignment.CenterVertically)) {
        Box(Modifier.height(260.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(230.dp).graphicsLayer { scaleX = 0.6f + 0.4f * a; scaleY = 0.6f + 0.4f * a }.blur(40.dp)
                .background(Brush.linearGradient(feature.colors.map { it.copy(alpha = 0.35f) }), CircleShape))
            Box(Modifier.size(210.dp).graphicsLayer { rotationZ = if (reduce) 0f else rotation }
                .border(1.5.dp, Brush.verticalGradient(feature.colors + Color.Transparent), CircleShape))
            Box(Modifier.size(150.dp).border(1.dp, Theme.primary.copy(alpha = 0.08f), CircleShape))
            IconTile(feature.symbol, 104.dp, feature.colors, Modifier.graphicsLayer { scaleX = 0.4f + 0.6f * a; scaleY = 0.4f + 0.6f * a; rotationZ = -18f * (1 - a) })
        }
        Column(Modifier.padding(horizontal = 32.dp).graphicsLayer { alpha = a; translationY = (1 - a) * 60f }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            T(feature.title, style = Type.system(32, FontWeight.ExtraBold).tracking(-0.6f), align = TextAlign.Center)
            T(feature.message, style = Type.body, color = Theme.secondary, align = TextAlign.Center)
        }
    }
}

/** Expanding neon capsule for the current page. */
@Composable
fun PageDots(count: Int, current: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(count) { index ->
            val width by animateDpAsState(if (index == current) 26.dp else 7.dp, spring(dampingRatio = 0.7f), label = "dot")
            Box(Modifier.width(width).height(7.dp).background(if (index == current) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.18f), Theme.primary.copy(alpha = 0.18f))), CircleShape))
        }
    }
}
