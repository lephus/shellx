package com.shellx.app.platform

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeviceNameTest {
    @Test
    fun theSettingNameComesFirst() {
        assertEquals("Phu's Pixel", DeviceName.of("  Phu's Pixel  ", "Pixel 9"))
    }

    @Test
    fun aBlankSettingFallsBackToTheModel() {
        assertEquals("Pixel 9", DeviceName.of(" ", "Pixel 9"))
        assertEquals("Pixel 9", DeviceName.of(null, "Pixel 9"))
    }

    @Test
    fun nothingAtAllIsAndroid() {
        assertEquals("Android", DeviceName.of(null, "  "))
    }

    @Test
    fun longNamesAreCutToTheRelaysLimit() {
        val accents = DeviceName.of("é".repeat(150), null)
        assertEquals(100, accents.codePointCount(0, accents.length))
        val phones = DeviceName.of("📱".repeat(120), null)
        assertEquals(100, phones.codePointCount(0, phones.length))
        assertTrue(Character.isLowSurrogate(phones.last()))
        assertEquals("📱".repeat(100), phones)
    }
}
