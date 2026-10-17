package com.easysesh.app.ui.components

import androidx.compose.runtime.staticCompositionLocalOf
import com.easysesh.app.AppState

/** The app state, available everywhere (iOS: @Environment(AppState.self)). */
val LocalAppState = staticCompositionLocalOf<AppState> { error("AppState not provided") }

/** App setting "Reduce visual effects". */
val LocalReduceEffects = staticCompositionLocalOf { false }
