package com.easysesh.app

import android.app.Application
import com.easysesh.app.core.L10n
import com.easysesh.app.services.PushNotifications

/** Holds the one AppState for the process, so it survives screen rotation and activity restarts. */
class EasySeshApplication : Application() {
    val appState: AppState by lazy { AppState(this) }

    override fun onCreate() {
        super.onCreate()
        L10n.load(this)
        PushNotifications.setUp(this)
    }
}
