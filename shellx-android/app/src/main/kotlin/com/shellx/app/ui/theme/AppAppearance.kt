package com.shellx.app.ui.theme

import androidx.annotation.StringRes
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import com.shellx.app.R
import com.shellx.core.platform.KeyValueStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Settings › Appearance: light, dark, or whatever the phone uses (the default), as `AppAppearance.swift`. */
enum class AppAppearance(val stored: String, @StringRes val title: Int) {
    SYSTEM("system", R.string.settings_appearance_system),
    LIGHT("light", R.string.settings_appearance_light),
    DARK("dark", R.string.settings_appearance_dark),
    ;

    /** Whether the app draws dark, when the phone is dark or not. */
    fun isDark(systemDark: Boolean): Boolean = when (this) {
        SYSTEM -> systemDark
        LIGHT -> false
        DARK -> true
    }

    companion object {
        /** The iPhone's `@AppStorage` key. */
        const val STORAGE_KEY = "shellx.appearance"

        /** The stored choice; anything unknown is "Match phone". */
        fun fromStored(value: String?): AppAppearance = entries.firstOrNull { it.stored == value } ?: SYSTEM
    }
}

/** Main-confined. Settings › Appearance, kept in the real account's settings (also during the demo). */
class AppAppearanceStore(private val settings: KeyValueStore) {
    private val _appearance = MutableStateFlow(AppAppearance.fromStored(settings.getString(AppAppearance.STORAGE_KEY)))
    val appearance: StateFlow<AppAppearance> = _appearance.asStateFlow()

    fun set(appearance: AppAppearance) {
        settings.putString(AppAppearance.STORAGE_KEY, appearance.stored)
        _appearance.value = appearance
    }
}

/** [ShellXTheme] in the chosen appearance: `ShellXTheme(darkTheme = appearance.isDark(isSystemInDarkTheme()))`. */
@Composable
fun ShellXAppTheme(appearance: AppAppearance, content: @Composable () -> Unit) {
    ShellXTheme(darkTheme = appearance.isDark(isSystemInDarkTheme()), content = content)
}
