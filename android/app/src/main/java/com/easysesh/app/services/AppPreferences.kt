package com.easysesh.app.services

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.easysesh.app.core.L10n
import java.io.File
import java.util.Locale

/** Languages the app ships in. Text falls back to English where a translation is missing. */
enum class AppLanguage(val code: String, val nativeName: String, val flag: String) {
    English("en", "English", "🇬🇧"),
    Danish("da", "Dansk", "🇩🇰"),
    German("de", "Deutsch", "🇩🇪"),
    Polish("pl", "Polski", "🇵🇱"),
    Greek("el", "Ελληνικά", "🇬🇷"),
    French("fr", "Français", "🇫🇷"),
    Spanish("es", "Español", "🇪🇸"),
    Italian("it", "Italiano", "🇮🇹"),
    Swedish("sv", "Svenska", "🇸🇪"),
    Dutch("nl", "Nederlands", "🇳🇱");

    companion object {
        fun from(code: String?) = entries.firstOrNull { it.code == code }

        /** Best match for the phone's language, English otherwise. */
        val deviceDefault: AppLanguage get() = from(Locale.getDefault().language) ?: English
    }
}

enum class AppAppearance(val raw: String, val title: String) {
    System("system", "Automatic"), Light("light", "Light"), Dark("dark", "Dark");

    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: System }
}

/** Device-level app settings (not tied to the account). */
class AppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("easysesh.prefs", Context.MODE_PRIVATE)

    var language by mutableStateOf(AppLanguage.from(prefs.getString(KEY_LANGUAGE, null)) ?: AppLanguage.deviceDefault)
        private set

    var appearance by mutableStateOf(AppAppearance.from(prefs.getString(KEY_APPEARANCE, null)))
        private set

    /** Turns off moving backgrounds, pulsing and glow animations. */
    var reduceEffects by mutableStateOf(prefs.getBoolean(KEY_REDUCE_EFFECTS, false))
        private set

    var hapticsEnabled by mutableStateOf(prefs.getBoolean(KEY_HAPTICS, true))
        private set

    var hasSeenIntro by mutableStateOf(prefs.getBoolean(KEY_INTRO, false))
        private set

    /** Studios whose "you're approved" tour was finished or skipped. */
    private var completedTours by mutableStateOf(prefs.getStringSet(KEY_TOURS, emptySet())!!.toSet())

    init {
        L10n.languageCode = language.code
    }

    fun updateLanguage(value: AppLanguage) {
        language = value
        L10n.languageCode = value.code
        prefs.edit().putString(KEY_LANGUAGE, value.code).apply()
    }

    fun updateAppearance(value: AppAppearance) {
        appearance = value
        prefs.edit().putString(KEY_APPEARANCE, value.raw).apply()
    }

    fun updateReduceEffects(value: Boolean) {
        reduceEffects = value
        prefs.edit().putBoolean(KEY_REDUCE_EFFECTS, value).apply()
    }

    fun updateHaptics(value: Boolean) {
        hapticsEnabled = value
        prefs.edit().putBoolean(KEY_HAPTICS, value).apply()
    }

    fun updateHasSeenIntro(value: Boolean) {
        hasSeenIntro = value
        prefs.edit().putBoolean(KEY_INTRO, value).apply()
    }

    fun hasCompletedTour(studioId: String) = studioId in completedTours
    fun completeTour(studioId: String) = setTours(completedTours + studioId)
    fun resetTour(studioId: String) = setTours(completedTours - studioId)

    private fun setTours(value: Set<String>) {
        completedTours = value
        prefs.edit().putStringSet(KEY_TOURS, value).apply()
    }

    // Changelog "seen" marker per account (iOS: UserDefaults easysesh.changelog.seen.<id>).
    fun changelogSeenAt(accountId: String): Long? = prefs.getLong("changelog.seen.$accountId", -1).takeIf { it >= 0 }
    fun setChangelogSeenAt(accountId: String, epochMillis: Long) = prefs.edit().putLong("changelog.seen.$accountId", epochMillis).apply()

    private companion object {
        const val KEY_LANGUAGE = "pref.language"
        const val KEY_APPEARANCE = "pref.appearance"
        const val KEY_REDUCE_EFFECTS = "pref.reduceEffects"
        const val KEY_HAPTICS = "pref.haptics"
        const val KEY_INTRO = "pref.hasSeenIntro"
        const val KEY_TOURS = "pref.completedTours"
    }
}

/** Downloaded images and temporary files. */
object AppCache {
    fun size(context: Context): Long = context.cacheDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    fun clear(context: Context) {
        context.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
        File(context.cacheDir, "image_cache").deleteRecursively()
    }
}
