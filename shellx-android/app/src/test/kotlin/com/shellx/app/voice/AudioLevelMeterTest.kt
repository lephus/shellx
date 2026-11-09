package com.shellx.app.voice

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AudioLevelMeterTest {
    @Test
    fun decibelsMapLinearlyAndClamp() {
        val meter = AudioLevelMeter()
        meter.update(-2f)
        assertEquals(0f, meter.level.value, 0f)
        meter.update(10f)
        assertEquals(1f, meter.level.value, 0f)
        meter.update(4f)
        assertEquals(0.5f, meter.level.value, 0.001f)
        meter.update(-30f)
        assertEquals(0f, meter.level.value, 0f)
        meter.update(40f)
        assertEquals(1f, meter.level.value, 0f)
        meter.reset()
        assertEquals(0f, meter.level.value, 0f)
    }
}
