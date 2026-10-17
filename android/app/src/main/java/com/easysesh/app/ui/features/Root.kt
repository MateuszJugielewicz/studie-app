package com.easysesh.app.ui.features

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.easysesh.app.AppState
import com.easysesh.app.model.UserRole
import com.easysesh.app.services.AppAppearance
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.EasySeshTheme
import com.easysesh.app.ui.theme.Theme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.foundation.isSystemInDarkTheme

/**
 * The whole app: intro or RootView underneath, with the animated "easysesh" splash on top until
 * the session is restored (and at least long enough for its animation to play).
 */
@Composable
fun EasySeshApp(app: AppState) {
    val preferences = app.preferences
    val dark = when (preferences.appearance) {
        AppAppearance.Light -> false
        AppAppearance.Dark -> true
        AppAppearance.System -> isSystemInDarkTheme()
    }
    var showSplash by remember { mutableStateOf(!app.launchFinished) }
    var revealed by remember { mutableStateOf(app.launchFinished) }

    LaunchedEffect(Unit) {
        if (app.launchFinished) return@LaunchedEffect
        val started = System.currentTimeMillis()
        app.bootstrap()
        // Let the splash animation finish even when loading is instant, and give the first
        // screen a moment to fill in before it's revealed.
        delay(maxOf(1400 - (System.currentTimeMillis() - started), 500))
        revealed = true
        delay(850)
        showSplash = false
        app.launchFinished = true
    }

    EasySeshTheme(dark) {
        CompositionLocalProvider(LocalAppState provides app, LocalReduceEffects provides preferences.reduceEffects) {
            PaymentProvider {
                Box(Modifier.fillMaxSize().background(Theme.background)) {
                    val scale by animateFloatAsState(if (revealed) 1f else 1.04f, tween(800), label = "reveal")
                    Box(Modifier.fillMaxSize().scale(scale)) {
                        AnimatedContent(preferences.hasSeenIntro, transitionSpec = { fadeIn(tween(500)) togetherWith fadeOut(tween(500)) }, label = "intro") { seen ->
                            if (seen) RootView() else IntroView()
                        }
                    }
                    if (showSplash) {
                        val alpha by animateFloatAsState(if (revealed) 0f else 1f, tween(800), label = "splashAlpha")
                        val splashScale by animateFloatAsState(if (revealed) 1.08f else 1f, tween(800), label = "splashScale")
                        Box(Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha; scaleX = splashScale; scaleY = splashScale }) { AnimatedSplashView() }
                    }
                }
                if (app.needsNewPassword) {
                    Sheet({ }) { ChangePasswordView(isRecovery = true) }
                }
            }
        }
    }
}

private enum class RootScreen { Splash, Terms, Artist, ArtistOnboarding, Studio, Admin, Guest, Welcome }

@Composable
fun RootView() {
    val app = LocalAppState.current
    val account = app.account
    val screen = when {
        app.isBootstrapping -> RootScreen.Splash
        app.needsTermsAcceptance -> RootScreen.Terms
        account != null -> when (account.role) {
            UserRole.Artist -> if (app.artistProfile?.isComplete == true) RootScreen.Artist else RootScreen.ArtistOnboarding
            UserRole.StudioOwner -> RootScreen.Studio
            UserRole.Admin -> RootScreen.Admin
        }
        app.isGuest -> RootScreen.Guest
        else -> RootScreen.Welcome
    }

    AnimatedContent(screen to account?.id, transitionSpec = { fadeIn(tween(450)) togetherWith fadeOut(tween(450)) }, label = "root") { (current, _) ->
        when (current) {
            RootScreen.Splash -> Box(Modifier.fillMaxSize().background(Theme.background))
            RootScreen.Terms -> TermsAcceptanceView()
            RootScreen.Artist -> ArtistTabView()
            RootScreen.ArtistOnboarding -> ArtistOnboardingView()
            RootScreen.Studio -> StudioOwnerRootView()
            RootScreen.Admin -> AdminInfoView()
            RootScreen.Guest -> GuestBrowseView()
            RootScreen.Welcome -> WelcomeView()
        }
    }

    // Warnings from the team come first, then "What's new".
    val warning = if (!app.launchFinished || app.needsTermsAcceptance) null else app.warnings.firstOrNull()
    if (warning != null) {
        Sheet({ }) { WarningSheet(warning) }
    } else if (app.launchFinished && !app.needsTermsAcceptance && account?.role != UserRole.Admin && app.unseenChangelog.isNotEmpty()) {
        Sheet({ app.markChangelogSeen() }) { WhatsNewSheet(app.unseenChangelog) }
    }

    // Coming back to the app checks for new update notes and warnings.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) app.scope.launch { app.refreshUpdates() }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
}

/**
 * Launch animation: the wordmark fades in from a blur, the neon dot drops in with a bounce and
 * a small equalizer pulses underneath until the app is ready.
 */
@Composable
fun AnimatedSplashView() {
    val reduceMotion = LocalReduceEffects.current
    var started by remember { mutableStateOf(reduceMotion) }
    LaunchedEffect(Unit) { started = true }
    val wordmark by animateFloatAsState(if (started) 1f else 0f, tween(if (reduceMotion) 0 else 700, easing = LinearOutSlowInEasing), label = "wordmark")
    val dot by animateFloatAsState(if (started) 1f else 0f, if (reduceMotion) tween(0) else spring(dampingRatio = 0.55f, stiffness = 160f), label = "dot")
    val infinite = rememberInfiniteTransition(label = "splash")
    val glow by infinite.animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "glow")
    val barHeights = listOf(0.45f, 0.8f, 1f, 0.65f, 0.9f, 0.5f, 0.75f)

    Box(Modifier.fillMaxSize().background(Theme.background), contentAlignment = Alignment.Center) {
        val g = if (reduceMotion) 1f else glow
        val glowColor = Theme.magenta
        Box(Modifier.size(520.dp).scale(0.85f + 0.3f * g).alpha(0.15f + 0.3f * g).background(androidx.compose.ui.graphics.Brush.radialGradient(listOf(glowColor, glowColor.copy(alpha = 0.35f), androidx.compose.ui.graphics.Color.Transparent))))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Txt(
                    "easysesh",
                    Modifier.alpha(wordmark).blur((12 * (1 - wordmark)).dp).scale(0.86f + 0.14f * wordmark),
                    style = Type.system(46, FontWeight.ExtraBold).tracking(-1.4f),
                )
                Box(
                    Modifier.padding(bottom = 12.dp).graphicsLayer { translationY = -60.dp.toPx() * (1 - dot); alpha = dot.coerceIn(0f, 1f) }
                        .size(12.dp).neonGlow(Theme.accent, (8 + 6 * g).dp, CircleShape).background(Theme.neon, CircleShape),
                )
            }
            Row(Modifier.height(26.dp).alpha(wordmark * 0.9f), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                barHeights.forEachIndexed { index, height ->
                    val bar by infinite.animateFloat(
                        0.2f, height,
                        infiniteRepeatable(tween(420 + (index % 3) * 120, delayMillis = index * 60, easing = FastOutSlowInEasing), RepeatMode.Reverse),
                        label = "bar$index",
                    )
                    Box(Modifier.width(4.dp).height((26 * if (reduceMotion) height else bar).dp).background(Theme.neon, CircleShape))
                }
            }
        }
    }
}

/** Admins use the web dashboard (admin/). The app only points them there. */
@Composable
fun AdminInfoView() {
    val app = LocalAppState.current
    Column(
        Modifier.fillMaxSize().auroraBackground().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    ) {
        Sym("shield.lefthalf.filled", size = 48.dp, tint = Theme.secondary)
        T("Admin account", style = Type.title2.bold, align = TextAlign.Center)
        T("Studio approvals, users, bookings, payments and moderation are managed in the EasySesh admin dashboard on the web.",
            style = Type.body, color = Theme.secondary, align = TextAlign.Center)
        PrimaryButton("Sign out", Modifier.fillMaxWidth().padding(top = 8.dp)) { app.scope.launch { app.signOut() } }
    }
}
