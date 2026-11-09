package com.shellx.core.platform

import kotlin.time.TimeSource

/** Time for the core. :app passes its Android clock (3D); tests pass ManualClock. */
interface Clock {
    /** Wall-clock time in epoch milliseconds, the scale of the Mac's `*_ms` fields. */
    fun nowMs(): Long

    /**
     * For stopwatches and "how long in the background": never goes back, and on Android keeps counting in deep
     * sleep (3D backs it with SystemClock.elapsedRealtimeNanos).
     */
    val monotonic: TimeSource.WithComparableMarks
}
