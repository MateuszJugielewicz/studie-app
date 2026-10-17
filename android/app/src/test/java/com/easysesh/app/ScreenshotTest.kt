package com.easysesh.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import com.easysesh.app.core.L10n
import com.easysesh.app.model.Studio
import com.easysesh.app.model.UserRole
import com.easysesh.app.model.ArtistProfile
import com.easysesh.app.ui.components.LocalAppState
import com.easysesh.app.ui.components.NavigationStack
import com.easysesh.app.ui.features.*
import com.easysesh.app.ui.theme.EasySeshTheme
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders screens to PNG files without a device, to compare them with the iOS app.
 * Run: ./gradlew :app:testDebugUnitTest --tests "*ScreenshotTest*" -Proborazzi.test.record=true
 * Images land in app/build/screenshots/.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w393dp-h852dp-xxhdpi", application = android.app.Application::class)
class ScreenshotTest {
    @get:Rule val compose = createComposeRule()

    private val app by lazy {
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        L10n.load(context)
        AppState(context)
    }

    private fun shot(name: String, dark: Boolean = false, content: @Composable () -> Unit) {
        compose.setContent {
            EasySeshTheme(dark) {
                CompositionLocalProvider(LocalAppState provides app) { NavigationStack { content() } }
            }
        }
        compose.mainClock.advanceTimeBy(2500)
        compose.onRoot().captureRoboImage("build/screenshots/$name.png")
    }

    @Test fun intro() = shot("01_intro") { IntroView() }
    @Test fun welcome() = shot("02_welcome") { WelcomeView() }
    @Test fun welcomeDark() = shot("02_welcome_dark", dark = true) { WelcomeView() }
    @Test fun auth() = shot("03_auth") { AuthView(AuthRoute.Mode.SignUp, UserRole.Artist) }
    @Test fun splash() = shot("04_splash", dark = true) { AnimatedSplashView() }
    @Test fun appSettings() = shot("05_app_settings") { AppSettingsView() }
    @Test fun changePassword() = shot("06_change_password") { ChangePasswordView() }
    @Test fun newTicket() = shot("07_new_ticket") { NewSupportTicketView(null) {} }
    @Test fun profileEditor() = shot("08_profile_editor") { ArtistProfileEditor(ArtistProfile.empty("a"), isOnboarding = true) }
    @Test fun studioEditor() = shot("09_studio_editor") { StudioEditorView(Studio.newDraft("o"), isApplication = true) }
    @Test fun studioPolicy() = shot("10_studio_policy") { StudioSectionEditor("Booking settings") { s, set -> StudioPolicyEditor(s, set) } }
    @Test fun applicationStatus() = shot("11_application") { ApplicationStatusView(Studio.newDraft("o").copy(name = "Night Owl Studio")) }
    @Test fun admin() = shot("12_admin", dark = true) { AdminInfoView() }
    @Test fun blockTime() = shot("13_block_time") { BlockTimeSheet("s", java.time.LocalDate.of(2026, 10, 20)) {} }
    @Test fun openingHours() = shot("14_opening_hours") {
        androidx.compose.runtime.key(1) {
            var hours by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(com.easysesh.app.model.OpeningHours.standardWeek) }
            com.easysesh.app.ui.components.NavScreen("Opening hours") { OpeningHoursEditor(hours) { hours = it } }
        }
    }
}
