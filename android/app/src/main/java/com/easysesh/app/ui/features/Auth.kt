package com.easysesh.app.ui.features

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.LinearEasing
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.easysesh.app.AuthRoute
import com.easysesh.app.BuildConfig
import com.easysesh.app.core.L10n
import com.easysesh.app.core.LegalDocument
import com.easysesh.app.core.PasswordPolicy
import com.easysesh.app.core.tr
import com.easysesh.app.data.userMessage
import com.easysesh.app.model.UserAccount
import com.easysesh.app.model.UserRole
import com.easysesh.app.ui.components.*
import com.easysesh.app.ui.theme.Theme
import com.easysesh.app.ui.theme.TilePalette
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.security.SecureRandom
import kotlin.math.sin

@Composable
fun WelcomeView() {
    val app = LocalAppState.current
    NavigationStack {
        val navigator = LocalNavigator.current
        Column(Modifier.fillMaxSize().auroraBackground(560.dp, animated = true).statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp).padding(bottom = 12.dp)) {
            Row(Modifier.padding(top = 8.dp)) { EasySeshLogo(26) }
            Spacer(Modifier.weight(1f).heightIn(min = 24.dp))
            LevelMeter(Modifier.fillMaxWidth().height(120.dp).padding(bottom = 28.dp))
            T("Studio time,\nbooked in minutes.", style = Type.display(40).tracking(-0.8f))
            T("Find rooms, gear and engineers near you. See real prices and availability, book and pay in one place.",
                Modifier.padding(top = 12.dp), style = Type.body, color = Theme.secondary)
            Spacer(Modifier.weight(1f).heightIn(min = 32.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryButton("Find a studio") { navigator?.push { AuthView(AuthRoute.Mode.SignUp, UserRole.Artist) } }
                SecondaryButton("List your studio") { navigator?.push { AuthView(AuthRoute.Mode.SignUp, UserRole.StudioOwner) } }
                Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { app.isGuest = true }, contentAlignment = Alignment.Center) {
                    T("Look around first", style = Type.subheadline.semibold, color = Theme.accent)
                }
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { navigator?.push { AuthView(AuthRoute.Mode.SignIn, UserRole.Artist) } },
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    T("Already have an account? ", style = Type.subheadline, color = Theme.secondary)
                    T("Sign in", style = Type.subheadline.semibold)
                }
            }
        }
    }
}

/** Discover without an account. Booking, messaging and the rest ask the guest to sign up. */
@Composable
fun GuestBrowseView() {
    val app = LocalAppState.current
    Column(Modifier.fillMaxSize().background(Theme.background)) {
        Box(Modifier.weight(1f)) { DiscoverView() }
        Row(
            Modifier.fillMaxWidth().background(Theme.card.copy(alpha = 0.95f)).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(36.dp).clip(CircleShape).clickable { app.isGuest = false }, contentAlignment = Alignment.Center) { Sym("xmark") }
            T("Create a free account to book and message studios.", Modifier.weight(1f), style = Type.footnote.semibold)
            PrimaryButton("Sign up", Modifier.width(110.dp)) { app.guestAuthRequest = AuthRoute(AuthRoute.Mode.SignUp, UserRole.Artist) }
        }
    }
    app.guestAuthRequest?.let { route ->
        Sheet(onDismiss = { app.guestAuthRequest = null }) { AuthView(route.mode, route.role) }
    }
}


/** A live "VU meter": bars breathe like a signal on a mixing desk. Static when effects are reduced. */
@Composable
fun LevelMeter(modifier: Modifier = Modifier) {
    val levels = listOf(0.22f, 0.35f, 0.3f, 0.52f, 0.44f, 0.7f, 0.62f, 0.9f, 0.78f, 1.0f, 0.84f, 0.66f, 0.74f, 0.5f, 0.58f, 0.4f, 0.46f, 0.28f, 0.34f, 0.18f)
    val reduce = LocalReduceEffects.current
    val time by rememberInfiniteTransition(label = "meter").animateFloat(0f, 10_000f, infiniteRepeatable(tween(10_000_000, easing = LinearEasing)), label = "t")
    val colors = listOf(Theme.violet, Theme.magenta, Theme.accent)
    Canvas(modifier) {
        val t = if (reduce) 0f else time
        val gap = 5.dp.toPx()
        val barWidth = (size.width - gap * (levels.size - 1)) / levels.size
        levels.forEachIndexed { index, base ->
            val wobble = (sin(t * 2.1f + index * 0.7f) + sin(t * 3.3f + index * 1.3f)) * 0.12f
            val level = (base + wobble).coerceIn(0.08f, 1f)
            val h = size.height * level
            drawRoundRect(
                Brush.verticalGradient(colors.reversed(), startY = size.height - h, endY = size.height),
                topLeft = Offset(index * (barWidth + gap), size.height - h),
                size = Size(barWidth, h),
                cornerRadius = CornerRadius(3.dp.toPx()),
                alpha = 0.35f + level * 0.65f,
            )
        }
    }
}

@Composable
fun AuthView(initialMode: AuthRoute.Mode, initialRole: UserRole) {
    val app = LocalAppState.current
    val context = LocalContext.current
    var mode by remember { mutableStateOf(initialMode) }
    var role by remember { mutableStateOf(initialRole) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var acceptedTerms by remember { mutableStateOf(false) }
    var isWorking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<String?>(null) }
    var legalDocument by remember { mutableStateOf<LegalDocument?>(null) }
    var showPassword by remember { mutableStateOf(false) }
    var focus by remember { mutableStateOf<String?>(null) }
    val signUp = mode == AuthRoute.Mode.SignUp
    val canSubmit = !isWorking && email.contains("@") && password.isNotEmpty() &&
        (!signUp || (acceptedTerms && PasswordPolicy.problem(password) == null))

    fun run(action: suspend () -> UserAccount) {
        isWorking = true
        app.scope.launch {
            try {
                app.didAuthenticate(action())
            } catch (e: Exception) {
                error = e.userMessage
            } finally {
                isWorking = false
            }
        }
    }

    fun submit() = run {
        if (signUp) app.backend.signUp(email.trim(), password, role) else app.backend.signIn(email.trim(), password)
    }

    fun google() {
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isEmpty()) {
            // No native client configured: sign in in the browser instead.
            app.pendingOAuthRole = role
            app.scope.launch { runCatching { app.backend.startOAuth("google") }.onFailure { error = it.userMessage } }
            return
        }
        val activity = context as? Activity ?: return
        run {
            val raw = Nonce.random()
            val option = GetGoogleIdOption.Builder()
                .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
                .setFilterByAuthorizedAccounts(false)
                .setNonce(Nonce.sha256(raw))
                .build()
            val result = try {
                CredentialManager.create(activity).getCredential(activity, GetCredentialRequest.Builder().addCredentialOption(option).build())
            } catch (e: GetCredentialCancellationException) {
                throw kotlinx.coroutines.CancellationException("cancelled")
            }
            val token = GoogleIdTokenCredential.createFrom(result.credential.data).idToken
            app.backend.signInWithGoogleIdToken(token, raw, role)
        }
    }

    fun apple() {
        app.pendingOAuthRole = role
        app.scope.launch { runCatching { app.backend.startOAuth("apple") }.onFailure { error = it.userMessage } }
    }

    NavScreen("", scrollable = false, auroraHeight = 520.dp) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            // Header
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                EasySeshLogo(26)
                T(if (signUp) "Create your account" else "Welcome back", Modifier.padding(top = 14.dp), style = Type.system(36, FontWeight.ExtraBold).tracking(-0.8f))
                T(if (signUp) "Book studios or list your own in minutes." else "Sign in to book, chat and manage your sessions.", style = Type.body, color = Theme.secondary)
            }
            AnimatedVisibility(signUp) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Eyebrow("I am")
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        RoleCard("Artist", "Find & book studios", "music.mic", TilePalette.signal, role == UserRole.Artist, Modifier.weight(1f)) { role = UserRole.Artist }
                        RoleCard("Studio owner", "List your studio", "building.2.fill", TilePalette.violet, role == UserRole.StudioOwner, Modifier.weight(1f)) { role = UserRole.StudioOwner }
                    }
                    T(if (role == UserRole.Artist) "Find and book studios, pay in the app or cash, and chat with studios about your sessions."
                    else "Studio accounts are separate from artist accounts. You get access to studio tools only after our team has reviewed and approved your studio.",
                        style = Type.footnote, color = Theme.secondary)
                }
            }
            // Social buttons
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SocialButton(if (signUp) "Sign up with Apple" else "Sign in with Apple", dark = true, onClick = { apple() }) {
                    Sym("person.crop.circle.fill", size = 20.dp, tint = if (Theme.colors.isDark) Color.Black else Color.White)
                }
                SocialButton("Continue with Google", dark = false, onClick = { google() }) {
                    GradientText("G", Brush.linearGradient(listOf(Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853))), Type.system(19, FontWeight.ExtraBold))
                }
            }
            // Divider
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.weight(1f).height(1.dp).background(Theme.primary.copy(alpha = 0.12f)))
                T("Or with email", style = Type.caption.semibold, color = Theme.secondary)
                Box(Modifier.weight(1f).height(1.dp).background(Theme.primary.copy(alpha = 0.12f)))
            }
            // Fields
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                GlassField("envelope.fill", focus == "email") {
                    PlainTextField(email, { email = it }, "Email", Modifier.weight(1f).onFocusChanged { if (it.isFocused) focus = "email" },
                        keyboard = KeyboardType.Email, capitalization = KeyboardCapitalization.None)
                }
                GlassField("lock.fill", focus == "password") {
                    PlainTextField(password, { password = it }, "Password", Modifier.weight(1f).onFocusChanged { if (it.isFocused) focus = "password" },
                        keyboard = KeyboardType.Password, capitalization = KeyboardCapitalization.None, secure = !showPassword)
                    Box(Modifier.clickable { showPassword = !showPassword }) { Sym(if (showPassword) "eye.slash.fill" else "eye.fill", tint = Theme.secondary) }
                }
                if (signUp && password.isNotEmpty()) PasswordStrengthMeter(password)
                if (!signUp) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        LinkButton("Forgot password?", style = Type.footnote.semibold, enabled = email.contains("@")) {
                            app.scope.launch {
                                try {
                                    app.backend.sendPasswordReset(email.trim())
                                    info = tr("Check your inbox for a reset link.")
                                } catch (e: Exception) { error = e.userMessage }
                            }
                        }
                    }
                }
            }
            if (signUp) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.clickable { acceptedTerms = !acceptedTerms }, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            Modifier.size(24.dp)
                                .then(if (acceptedTerms) Modifier.neonGlow(Theme.magenta, 6.dp, CircleShape) else Modifier)
                                .background(if (acceptedTerms) Theme.neon else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)), CircleShape)
                                .border(1.5.dp, Theme.primary.copy(alpha = if (acceptedTerms) 0f else 0.25f), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) { if (acceptedTerms) Sym("checkmark", size = 14.dp, tint = Color.White) }
                        T(if (role == UserRole.StudioOwner) "I accept the Terms, the Studio Agreement and the Privacy Policy" else "I accept the Terms and the Privacy Policy",
                            style = Type.footnote)
                    }
                    FlowLayout(modifier = Modifier.padding(start = 36.dp)) {
                        LegalDocument.required(role).forEach { document ->
                            Row(
                                Modifier.background(Theme.card.copy(alpha = 0.6f), CircleShape).border(1.dp, Theme.primary.copy(alpha = 0.1f), CircleShape)
                                    .clickable { legalDocument = document }.padding(horizontal = 10.dp, vertical = 6.dp),
                                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Sym("doc.text", size = 13.dp)
                                T(document.title, style = Type.caption.semibold)
                            }
                        }
                    }
                }
            }
            // Submit
            Box(Modifier.padding(top = 4.dp)) {
                PrimaryButton(if (signUp) "Create account" else "Sign in", enabled = canSubmit, symbol = null) { submit() }
                if (isWorking) Box(Modifier.matchParentSizeBox(), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp) }
            }
            // Footer
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                T(if (signUp) "Already have an account?" else "New to EasySesh?", style = Type.subheadline, color = Theme.secondary)
                HSpace(4.dp)
                GradientText(tr(if (signUp) "Sign in" else "Create account"), Theme.neon, Type.subheadline.bold,
                    Modifier.clickable { mode = if (signUp) AuthRoute.Mode.SignIn else AuthRoute.Mode.SignUp; focus = null })
            }
        }
    }
    legalDocument?.let { document -> Sheet(onDismiss = { legalDocument = null }) { LegalDocumentView(document) } }
    ErrorAlert(error) { error = null }
    info?.let { InfoAlert("Email sent", it) { info = null } }
}

private fun Modifier.matchParentSizeBox() = this.then(Modifier.fillMaxWidth().height(54.dp))

@Composable
private fun SocialButton(title: String, dark: Boolean, onClick: () -> Unit, icon: @Composable () -> Unit) {
    // "Dark" = the Sign in with Apple style: black in light mode, white in dark mode.
    val background = if (dark) (if (Theme.colors.isDark) Color.White else Color.Black) else Theme.card.copy(alpha = 0.6f)
    val foreground = if (dark) (if (Theme.colors.isDark) Color.Black else Color.White) else Theme.primary
    Row(
        Modifier.fillMaxWidth().height(54.dp)
            .neonGlow(Color.Black.copy(alpha = 0.3f), 12.dp, CircleShape, dark)
            .background(background, CircleShape)
            .border(1.dp, if (dark) Color.Transparent else Theme.primary.copy(alpha = 0.14f), CircleShape)
            .pressable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        HSpace(10.dp)
        T(title, style = Type.body.semibold, color = foreground)
    }
}

object Nonce {
    fun random(length: Int = 32): String {
        val charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        val random = SecureRandom()
        return (1..length).map { charset[random.nextInt(charset.length)] }.joinToString("")
    }

    fun sha256(input: String): String =
        MessageDigest.getInstance("SHA-256").digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
}

/** Selectable card for "Artist" / "Studio owner". */
@Composable
private fun RoleCard(title: String, subtitle: String, symbol: String, colors: List<Color>, isSelected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .then(if (isSelected) Modifier.neonGlow(Theme.magenta, 12.dp, shape) else Modifier)
            .background(Theme.card.copy(alpha = 0.7f), shape)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.1f), Theme.primary.copy(alpha = 0.1f))), shape)
            .pressable(onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            IconTile(symbol, 38.dp, if (isSelected) colors else TilePalette.muted)
            Fill()
            Sym(if (isSelected) "checkmark.circle.fill" else "circle", size = 22.dp, tint = if (isSelected) Theme.magenta else Theme.secondary.copy(alpha = 0.5f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            T(title, style = Type.subheadline.heavy)
            T(subtitle, style = Type.caption, color = Theme.secondary)
        }
    }
}

/** Frosted input row with a leading icon; glows while focused. */
@Composable
fun GlassField(symbol: String, isFocused: Boolean, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().height(56.dp)
            .then(if (isFocused) Modifier.neonGlow(Theme.magenta, 10.dp, shape) else Modifier)
            .background(Theme.card.copy(alpha = 0.7f), shape)
            .border(if (isFocused) 1.6.dp else 1.dp, if (isFocused) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.1f), Theme.primary.copy(alpha = 0.1f))), shape)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) { Sym(symbol, size = 17.dp, tint = if (isFocused) Theme.magenta else Theme.secondary) }
        content()
    }
}

/** Four neon segments that fill up as the password gets stronger. */
@Composable
private fun PasswordStrengthMeter(password: String) {
    var points = 0
    if (password.length >= PasswordPolicy.MINIMUM_LENGTH) points++
    if (password.length >= 14) points++
    if (password.any { it.isDigit() } && password.any { it.isLetter() }) points++
    if (password.any { it.isUpperCase() } && password.any { !it.isLetterOrDigit() }) points++
    val score = if (PasswordPolicy.problem(password) == null) maxOf(points, 1) else minOf(points, 1)
    val label = when (score) { 0, 1 -> "Too weak"; 2 -> "Okay"; 3 -> "Strong"; else -> "Very strong" }
    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(4) { index ->
                Box(Modifier.weight(1f).height(5.dp).background(if (index < score) Theme.neon else Brush.linearGradient(listOf(Theme.primary.copy(alpha = 0.1f), Theme.primary.copy(alpha = 0.1f))), CircleShape))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            T(label, style = Type.caption.bold)
            Fill()
            PasswordPolicy.problem(password)?.let { Txt(it, style = Type.caption, color = Theme.warning) }
        }
    }
}
