package com.shellx.app.platform

import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.math.abs
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.shadows.ShadowSystemClock

@RunWith(AndroidJUnit4::class)
class AndroidClockTest {
    @Test
    fun monotonicCountsTheTimeTheSystemClockMoved() {
        val mark = AndroidClock.monotonic.markNow()
        ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(26))
        assertEquals(26.seconds, mark.elapsedNow())
    }

    @Test
    fun wallTimeIsEpochMilliseconds() {
        assertTrue(abs(AndroidClock.nowMs() - System.currentTimeMillis()) < 1_000)
    }
}
