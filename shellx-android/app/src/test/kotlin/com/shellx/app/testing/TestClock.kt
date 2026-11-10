package com.shellx.app.testing

import com.shellx.core.platform.Clock
import kotlin.time.TimeSource

/** The real wall clock and the real monotonic source, for tests that run on real time (Compose UI tests, [WorkRig]). */
object TestClock : Clock {
    override fun nowMs(): Long = System.currentTimeMillis()

    override val monotonic: TimeSource.WithComparableMarks get() = TimeSource.Monotonic
}
