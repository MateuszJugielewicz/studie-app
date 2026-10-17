package com.easysesh.app.core

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Locale

/**
 * Translations in the language picked in the app, applied immediately. The same string catalog as
 * the iOS app (ios/EasySesh/Localizable.xcstrings, copied into the APK by Gradle): English text is
 * the key, so `tr("Book")` shows "Book" in English and "Book" in Danish, etc.
 */
object L10n {
    /** Observable so composables update the moment the language changes. */
    var languageCode by mutableStateOf("en")

    private var table: Map<String, Map<String, String>> = emptyMap()

    fun load(context: Context) {
        if (table.isNotEmpty()) return
        val text = runCatching { context.assets.open("l10n/Localizable.xcstrings").bufferedReader().use { it.readText() } }.getOrNull() ?: return
        val strings = Json.parseToJsonElement(text).jsonObject["strings"]?.jsonObject ?: return
        val result = HashMap<String, MutableMap<String, String>>()
        for ((key, entry) in strings) {
            val localizations = entry.jsonObject["localizations"]?.jsonObject ?: continue
            for ((lang, value) in localizations) {
                val translated = value.jsonObject["stringUnit"]?.jsonObject?.get("value")?.jsonPrimitive?.content ?: continue
                result.getOrPut(lang) { HashMap() }[key] = translated
            }
        }
        table = result
    }

    /** The translation of `key`, or the key itself (English) when there is none. */
    fun tr(key: String): String {
        val code = languageCode
        if (code == "en" || key.isEmpty()) return key
        return table[code]?.get(key) ?: key
    }

    /** Translates a format key such as "Until %@." (iOS format specifiers) and fills in the values. */
    fun format(key: String, vararg args: Any?): String {
        val pattern = javaFormat(tr(key))
        return runCatching { String.format(locale(), pattern, *args) }.getOrElse { pattern }
    }

    fun locale(): Locale = Locale(languageCode)

    private val specifier = Regex("""%(\d+\$)?(@|lld|ld|lu|llu|d|i|u|f|\.\d+f|s)""")

    /** "%@" → "%s", "%lld" → "%d", "%1$@" → "%1$s" (iOS → Java). */
    fun javaFormat(pattern: String): String = specifier.replace(pattern) { m ->
        val position = m.groupValues[1]
        val spec = when (val s = m.groupValues[2]) {
            "@", "s" -> "s"
            "lld", "ld", "lu", "llu", "d", "i", "u" -> "d"
            else -> s
        }
        "%$position$spec"
    }
}

fun tr(key: String) = L10n.tr(key)
