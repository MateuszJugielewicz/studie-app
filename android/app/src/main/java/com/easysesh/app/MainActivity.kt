package com.easysesh.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.easysesh.app.services.DeepLink
import com.easysesh.app.services.PushNotifications
import com.easysesh.app.ui.features.EasySeshApp
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val app get() = (application as EasySeshApplication).appState

    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        app.location.onPermissionResult()
    }

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) PushNotifications.register()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        app.location.permissionRequester = {
            locationPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
        }
        PushNotifications.permissionRequester = {
            if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        handle(intent)
        setContent { EasySeshApp(app) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onDestroy() {
        app.location.permissionRequester = null
        PushNotifications.permissionRequester = null
        super.onDestroy()
    }

    /** Push notification taps and easysesh:// links (email confirmation, password reset, browser sign-in). */
    private fun handle(intent: Intent?) {
        intent ?: return
        DeepLink.from(intent)?.let { app.open(it) }
        val data = intent.data ?: return
        if (data.scheme != "easysesh") return
        // easysesh://payouts/… is Stripe onboarding returning; the payout screen handles it.
        if (data.host == "payouts") return
        val isRecovery = (data.fragment ?: "").contains("type=recovery") || data.getQueryParameter("type") == "recovery" ||
            app.backend.consumeRecoveryRequest()
        app.backend.handleDeeplink(intent) {
            app.scope.launch { app.completeAuthLink(isRecovery) }
        }
    }
}
