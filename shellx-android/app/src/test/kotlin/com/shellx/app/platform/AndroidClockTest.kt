package com.shellx.app.platform

import android.os.SystemClock
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
    fun monotonicCountsDeepSleep() { // ledger A-7; review A M-4: uptime stops in deep sleep, elapsed realtime does not
        val mark = AndroidClock.monotonic.markNow()
        val uptime = SystemClock.uptimeMillis()
        ShadowSystemClock.simulateDeepSleep(java.time.Duration.ofSeconds(40))
        assertEquals(uptime, SystemClock.uptimeMillis())
        assertEquals(40.seconds, mark.elapsedNow())
    }

    @Test
    fun wallTimeIsEpochMilliseconds() {
        assertTrue(abs(AndroidClock.nowMs() - System.currentTimeMillis()) < 1_000)
    }
}
