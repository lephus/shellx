package com.shellx.app.ui.theme

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.platform.MemoryKeyValueStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Settings › Appearance: what is stored, and which choice is dark (port of AppearanceTests.swift). */
@RunWith(AndroidJUnit4::class)
class AppAppearanceTest {
    @Test
    fun storedChoiceDefaultsToMatchPhone() {
        assertEquals(AppAppearance.SYSTEM, AppAppearance.fromStored(null))
        assertEquals("an unknown value is not a crash", AppAppearance.SYSTEM, AppAppearance.fromStored("sepia"))
        for (appearance in AppAppearance.entries) {
            assertEquals(appearance, AppAppearance.fromStored(appearance.stored))
        }
    }

    @Test
    fun eachChoiceDecidesDarkness() {
        assertTrue(AppAppearance.SYSTEM.isDark(systemDark = true))
        assertFalse(AppAppearance.SYSTEM.isDark(systemDark = false))
        assertFalse(AppAppearance.LIGHT.isDark(systemDark = true))
        assertTrue(AppAppearance.DARK.isDark(systemDark = false))
    }

    @Test
    fun theStoreKeepsTheChoice() {
        val settings = MemoryKeyValueStore()
        val store = AppAppearanceStore(settings)
        assertEquals(AppAppearance.SYSTEM, store.appearance.value)

        store.set(AppAppearance.DARK)

        assertEquals("dark", settings.getString("shellx.appearance"))
        assertEquals(AppAppearance.DARK, store.appearance.value)
        assertEquals(AppAppearance.DARK, AppAppearanceStore(settings).appearance.value)
    }
}
