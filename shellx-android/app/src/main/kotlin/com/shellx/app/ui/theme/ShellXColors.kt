package com.shellx.app.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

/**
 * The ShellX colour tokens, the same as the iPhone's: the colour sets in `shellx-ios/ShellX/Assets.xcassets`, and
 * [onAccent] from `ShellX/UI/Components/PrimaryButtonStyle.swift`.
 *
 * Text drawn in the accent colour (text buttons, links) uses [accentText], as the iPhone's
 * `SecondaryButtonStyle` does: [accent] (#60A5FA) on white is only 2.5:1. [accent] is for fills, such as
 * the primary button, with [onAccent] on top.
 */
@Immutable
data class ShellXColors(
    val background: Color,
    val surface: Color,
    val accent: Color,
    val onAccent: Color,
    val accentText: Color,
    val bubbleMine: Color,
    val statusDone: Color,
    val statusError: Color,
    val statusIdle: Color,
    val statusNeedsYou: Color,
    val statusRunning: Color,
) {
    companion object {
        val Light = ShellXColors(
            background = Color(0xFFF2F2F7),
            surface = Color(0xFFFFFFFF),
            accent = Color(0xFF60A5FA),
            onAccent = Color(0xFF0B1220),
            accentText = Color(0xFF2563EB),
            bubbleMine = Color(0xFFDBEAFE),
            statusDone = Color(0xFF16A34A),
            statusError = Color(0xFFDC2626),
            statusIdle = Color(0xFF6B7280),
            statusNeedsYou = Color(0xFF2563EB),
            statusRunning = Color(0xFFCA8A04),
        )

        val Dark = ShellXColors(
            background = Color(0xFF0B0716),
            surface = Color(0xFF17122A),
            accent = Color(0xFF60A5FA),
            onAccent = Color(0xFF0B1220),
            accentText = Color(0xFF60A5FA),
            bubbleMine = Color(0xFF24364F),
            statusDone = Color(0xFF4ADE80),
            statusError = Color(0xFFF87171),
            statusIdle = Color(0xFF8B919C),
            statusNeedsYou = Color(0xFF60A5FA),
            statusRunning = Color(0xFFFACC15),
        )
    }
}
