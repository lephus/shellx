package com.shellx.core.link

import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.eventually
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class NetworkChangeFilterTest {
    private val wifi = NetworkPath("satisfied", listOf("wifi:en0"), listOf("192.168.1.1:0"))

    @Test fun firstPathIsTheBaseline() { runTest {
        val sleeper = ManualSleeper()
        var calls = 0
        val filter = NetworkChangeFilter(backgroundScope, sleeper.sleep) { calls++ }

        filter.receive(wifi)
        filter.receive(wifi)

        runCurrent()
        assertEquals(emptyList(), sleeper.requested)
        assertEquals(0, calls)
    } }

    @Test fun changesWithin300msReportedOnce() { runTest {
        val sleeper = ManualSleeper()
        var calls = 0
        val filter = NetworkChangeFilter(backgroundScope, sleeper.sleep) { calls++ }
        filter.receive(wifi)

        val cellular = NetworkPath("satisfied", listOf("cellular:pdp_ip0"), listOf("10.0.0.1:0"))
        val offline = NetworkPath("unsatisfied", emptyList(), emptyList())
        filter.receive(offline)
        eventually { sleeper.waiting.size == 1 }
        filter.receive(cellular)
        val settled = eventually { sleeper.waiting.size == 1 && sleeper.cancelled == 1 }
        assertTrue(settled, "the second change restarts the wait")
        assertEquals(listOf(NetworkChangeFilter.SETTLE), sleeper.waiting)
        assertEquals(300.milliseconds, NetworkChangeFilter.SETTLE)

        sleeper.release()
        val called = eventually { calls == 1 }
        assertTrue(called)
        assertEquals(2, sleeper.requested.size)
    } }

    @Test fun secondaryInterfaceDoesNotCount() { runTest {
        val sleeper = ManualSleeper()
        var calls = 0
        val filter = NetworkChangeFilter(backgroundScope, sleeper.sleep) { calls++ }
        filter.receive(wifi)

        // Cellular comes up behind Wi-Fi: the live sessions still use Wi-Fi.
        filter.receive(NetworkPath("satisfied", listOf("wifi:en0", "cellular:pdp_ip0"), listOf("192.168.1.1:0")))
        runCurrent()
        assertEquals(emptyList(), sleeper.requested)

        // Another Wi-Fi network: same interface, new gateway.
        filter.receive(NetworkPath("satisfied", listOf("wifi:en0"), listOf("10.1.1.1:0")))
        eventually { sleeper.waiting.size == 1 }
        sleeper.release()
        val called = eventually { calls == 1 }
        assertTrue(called)
    } }

    @Test fun gatewayOrderDoesNotCount() {
        assertEquals(
            NetworkPath("satisfied", listOf("wifi:en0"), listOf("a", "b")),
            NetworkPath("satisfied", listOf("wifi:en0", "other:utun0"), listOf("b", "a")),
        )
    }
}
