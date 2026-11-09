package com.shellx.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** The ShellX tokens of the current theme. Read them through [ShellXTheme.colors]. */
val LocalShellXColors: ProvidableCompositionLocal<ShellXColors> = staticCompositionLocalOf { ShellXColors.Light }

/**
 * The Material 3 colours of ShellX, made from [ShellXColors]. The roles the tokens do not cover use the iOS
 * system colours (labels, separators), so Material components look like the iPhone app.
 *
 * M3 `surface` (and `background`) is the screen colour: the iPhone's `Background`. Cards, sheets, dialogs, menus
 * and text fields sit on the `surfaceContainer*` roles, which are the iPhone's `Surface`.
 */
internal fun shellXColorScheme(dark: Boolean): ColorScheme {
    val c = if (dark) ShellXColors.Dark else ShellXColors.Light
    val black = Color(0xFF000000)
    val white = Color(0xFFFFFFFF)
    val label = if (dark) white else black
    val onAccentText = if (dark) Color(0xFF0B1220) else white
    // The Fixed roles look the same in both modes.
    val fixed = Color(0xFFDBEAFE)
    val fixedDim = Color(0xFF60A5FA)
    val onFixed = Color(0xFF0B1220)
    val onFixedVariant = Color(0xFF2563EB)
    return if (dark) {
        darkColorScheme(
            primary = c.accent, onPrimary = c.onAccent,
            primaryContainer = c.bubbleMine, onPrimaryContainer = label,
            inversePrimary = Color(0xFF2563EB),
            secondary = c.accentText, onSecondary = onAccentText,
            secondaryContainer = c.bubbleMine, onSecondaryContainer = label,
            tertiary = c.accentText, onTertiary = onAccentText,
            tertiaryContainer = c.bubbleMine, onTertiaryContainer = label,
            background = c.background, onBackground = label,
            surface = c.background, onSurface = label,
            surfaceVariant = c.surface, onSurfaceVariant = Color(0x99EBEBF5),
            surfaceTint = c.background,
            inverseSurface = Color(0xFFF2F2F7), inverseOnSurface = black,
            error = c.statusError, onError = Color(0xFF0B0716),
            errorContainer = Color(0xFF450A0A), onErrorContainer = Color(0xFFFECACA),
            outline = Color(0xFF38383A), outlineVariant = Color(0x99545458),
            scrim = black,
            surfaceBright = c.surface, surfaceDim = c.background,
            surfaceContainer = c.surface, surfaceContainerHigh = c.surface, surfaceContainerHighest = c.surface,
            surfaceContainerLow = c.surface, surfaceContainerLowest = c.surface,
            primaryFixed = fixed, primaryFixedDim = fixedDim, onPrimaryFixed = onFixed, onPrimaryFixedVariant = onFixedVariant,
            secondaryFixed = fixed, secondaryFixedDim = fixedDim, onSecondaryFixed = onFixed, onSecondaryFixedVariant = onFixedVariant,
            tertiaryFixed = fixed, tertiaryFixedDim = fixedDim, onTertiaryFixed = onFixed, onTertiaryFixedVariant = onFixedVariant,
        )
    } else {
        lightColorScheme(
            primary = c.accent, onPrimary = c.onAccent,
            primaryContainer = c.bubbleMine, onPrimaryContainer = label,
            inversePrimary = Color(0xFF60A5FA),
            secondary = c.accentText, onSecondary = onAccentText,
            secondaryContainer = c.bubbleMine, onSecondaryContainer = label,
            tertiary = c.accentText, onTertiary = onAccentText,
            tertiaryContainer = c.bubbleMine, onTertiaryContainer = label,
            background = c.background, onBackground = label,
            surface = c.background, onSurface = label,
            surfaceVariant = c.surface, onSurfaceVariant = Color(0x993C3C43),
            surfaceTint = c.background,
            inverseSurface = Color(0xFF17122A), inverseOnSurface = white,
            error = c.statusError, onError = white,
            errorContainer = Color(0xFFFEE2E2), onErrorContainer = Color(0xFF7F1D1D),
            outline = Color(0xFFC6C6C8), outlineVariant = Color(0x4A3C3C43),
            scrim = black,
            surfaceBright = c.surface, surfaceDim = c.background,
            surfaceContainer = c.surface, surfaceContainerHigh = c.surface, surfaceContainerHighest = c.surface,
            surfaceContainerLow = c.surface, surfaceContainerLowest = c.surface,
            primaryFixed = fixed, primaryFixedDim = fixedDim, onPrimaryFixed = onFixed, onPrimaryFixedVariant = onFixedVariant,
            secondaryFixed = fixed, secondaryFixedDim = fixedDim, onSecondaryFixed = onFixed, onSecondaryFixedVariant = onFixedVariant,
            tertiaryFixed = fixed, tertiaryFixedDim = fixedDim, onTertiaryFixed = onFixed, onTertiaryFixedVariant = onFixedVariant,
        )
    }
}

/**
 * The ShellX theme: the iPhone's colours in light or dark, following the system for now (3D adds the
 * Settings › Appearance switch). There is no dynamic colour, and the typography is Material's default.
 */
@Composable
fun ShellXTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) ShellXColors.Dark else ShellXColors.Light
    CompositionLocalProvider(LocalShellXColors provides colors) {
        MaterialTheme(colorScheme = shellXColorScheme(darkTheme), content = content)
    }
}

object ShellXTheme {
    /** The ShellX tokens of the current theme. */
    val colors: ShellXColors
        @Composable @ReadOnlyComposable get() = LocalShellXColors.current
}
