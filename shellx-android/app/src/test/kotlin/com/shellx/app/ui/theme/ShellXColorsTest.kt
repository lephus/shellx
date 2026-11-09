package com.shellx.app.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import org.junit.Assert.assertEquals
import org.junit.Test

class ShellXColorsTest {
    private fun assertArgb(what: String, expected: Long, actual: Color) =
        assertEquals(what, expected.toInt(), actual.toArgb())

    @Test
    fun lightTokensAreTheIPhoneColours() = with(ShellXColors.Light) {
        assertArgb("background", 0xFFF2F2F7, background); assertArgb("surface", 0xFFFFFFFF, surface)
        assertArgb("accent", 0xFF60A5FA, accent); assertArgb("onAccent", 0xFF0B1220, onAccent)
        assertArgb("accentText", 0xFF2563EB, accentText); assertArgb("bubbleMine", 0xFFDBEAFE, bubbleMine)
        assertArgb("statusDone", 0xFF16A34A, statusDone); assertArgb("statusError", 0xFFDC2626, statusError)
        assertArgb("statusIdle", 0xFF6B7280, statusIdle); assertArgb("statusNeedsYou", 0xFF2563EB, statusNeedsYou)
        assertArgb("statusRunning", 0xFFCA8A04, statusRunning)
    }

    @Test
    fun darkTokensAreTheIPhoneColours() = with(ShellXColors.Dark) {
        assertArgb("background", 0xFF0B0716, background); assertArgb("surface", 0xFF17122A, surface)
        assertArgb("accent", 0xFF60A5FA, accent); assertArgb("onAccent", 0xFF0B1220, onAccent)
        assertArgb("accentText", 0xFF60A5FA, accentText); assertArgb("bubbleMine", 0xFF24364F, bubbleMine)
        assertArgb("statusDone", 0xFF4ADE80, statusDone); assertArgb("statusError", 0xFFF87171, statusError)
        assertArgb("statusIdle", 0xFF8B919C, statusIdle); assertArgb("statusNeedsYou", 0xFF60A5FA, statusNeedsYou)
        assertArgb("statusRunning", 0xFFFACC15, statusRunning)
    }

    @Test
    fun materialRolesUseTheShellXColours() {
        for (dark in listOf(false, true)) {
            val c = if (dark) ShellXColors.Dark else ShellXColors.Light
            val s = shellXColorScheme(dark)
            assertEquals(c.accent, s.primary); assertEquals(c.onAccent, s.onPrimary)
            assertEquals(c.bubbleMine, s.primaryContainer); assertEquals(c.accentText, s.secondary)
            assertEquals(c.background, s.background); assertEquals(c.background, s.surface)
            assertEquals(c.background, s.surfaceTint); assertEquals(c.surface, s.surfaceContainer)
            assertEquals(c.surface, s.surfaceContainerLowest); assertEquals(c.surface, s.surfaceContainerHighest)
            assertEquals(c.statusError, s.error)
        }
        assertArgb("light onSurface", 0xFF000000, shellXColorScheme(false).onSurface)
        assertArgb("dark onSurface", 0xFFFFFFFF, shellXColorScheme(true).onSurface)
        assertArgb("light onSurfaceVariant", 0x993C3C43, shellXColorScheme(false).onSurfaceVariant)
        assertArgb("dark onSurfaceVariant", 0x99EBEBF5, shellXColorScheme(true).onSurfaceVariant)
        assertArgb("light outline", 0xFFC6C6C8, shellXColorScheme(false).outline)
    }
}
