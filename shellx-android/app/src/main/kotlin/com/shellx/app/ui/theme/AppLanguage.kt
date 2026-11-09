package com.shellx.app.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import java.util.Locale

/**
 * The language the app's strings show in (the iPhone's `Locale.app`), not the region's, so numbers and durations put
 * into a sentence match the words around them: Vietnamese when the locale's language is "vi", else English.
 */
object AppLanguage {
    private val vietnamese: Locale = Locale.forLanguageTag("vi")
    private val english: Locale = Locale.forLanguageTag("en")

    fun of(locale: Locale): Locale = if (locale.language == "vi") vietnamese else english

    /** The language of the current configuration (it follows a language change without a restart). */
    @Composable
    @ReadOnlyComposable
    fun current(): Locale = of(LocalConfiguration.current.locales[0])
}
