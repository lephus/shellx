package com.shellx.app.platform

import android.os.SystemClock
import com.shellx.core.platform.Clock
import kotlin.time.AbstractLongTimeSource
import kotlin.time.DurationUnit
import kotlin.time.TimeSource

/** Counts deep sleep (SystemClock.elapsedRealtimeNanos), as 3C's Clock.monotonic requires (ledger A-7). */
object ElapsedRealtimeTimeSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS) {
    override fun read(): Long = SystemClock.elapsedRealtimeNanos()
}

/** The app's clock: wall time in epoch milliseconds, and a monotonic clock that keeps counting in deep sleep. */
object AndroidClock : Clock {
    override fun nowMs(): Long = System.currentTimeMillis()

    override val monotonic: TimeSource.WithComparableMarks = ElapsedRealtimeTimeSource
}
