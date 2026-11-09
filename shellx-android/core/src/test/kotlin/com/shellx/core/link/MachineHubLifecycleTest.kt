package com.shellx.core.link

import com.shellx.core.demo.FakeMac
import com.shellx.core.testing.Gate
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.allOnline
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.pendingItem
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PermissionMode
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class MachineHubLifecycleTest {
    private fun model(hub: MachineHub, mac: FakeMac): MachineModel? = hub.machines.firstOrNull { it.id == mac.machine.machineId }

    // Ported from MachineHubTests.swift

    @Test fun pathChangeForcesReconnect() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        a.addPending(pendingItem("a1"))
        b.failNextConnects(IOException("offline"), 1)
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a, b), sleeper = sleeper)
        rig.hub.start()
        val settled = eventually {
            model(rig.hub, b)?.state is MachineLinkState.Offline &&
                model(rig.hub, a)?.state == MachineLinkState.Online && sleeper.waiting.size == 1
        }
        assertTrue(settled, "${rig.hub.machines.map { it.state }}")

        // Wi-Fi to cellular: the live session may be dead without anyone knowing yet.
        rig.hub.networkChanged()

        val reconnected = eventually { a.connectCount == 2 && b.connectCount == 2 && allOnline(rig.hub) }
        assertTrue(reconnected, "${rig.hub.machines.map { it.state }}")
        assertEquals(1, sleeper.cancelled, "the offline Mac skipped the rest of its backoff")
        assertTrue(eventually { a.liveSessionCount == 1 }, "the old session to MacBook Pro was closed")
        assertEquals(listOf(true), rig.hub.pendingItems.map { it.actionable })
    } }

    @Test fun backgroundClosesAfterGrace() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.addPending(pendingItem("a1"))
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a), sleeper = sleeper)
        rig.hub.start()
        eventually { allOnline(rig.hub) }

        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { sleeper.waiting == listOf(MachineHub.BACKGROUND_GRACE) }, "${sleeper.waiting}")
        assertEquals(25.seconds, MachineHub.BACKGROUND_GRACE)
        assertEquals(1, a.liveSessionCount, "nothing closes during the grace")

        sleeper.release()
        background.join()

        assertTrue(eventually { a.liveSessionCount == 0 })
        assertNotEquals(MachineLinkState.Online, model(rig.hub, a)?.state)
        assertEquals(listOf(false), rig.hub.pendingItems.map { it.actionable })
        assertSameCase(
            LinkCallException.Offline("MacBook Pro"),
            assertFails {
                rig.hub.reply(PendingKey(a.machine.machineId, "a1"), LinkDecision.Permission(PermissionMode.ONCE))
            },
        )

        rig.hub.appDidBecomeActive()
        val back = eventually { allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) }
        assertTrue(back, "${rig.hub.machines.map { it.state }}")
        assertEquals(2, a.connectCount)
    } }

    @Test fun quickReturnKeepsSessions() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a), sleeper = sleeper)
        rig.hub.start()
        eventually { allOnline(rig.hub) }

        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        eventually { sleeper.waiting == listOf(MachineHub.BACKGROUND_GRACE) }

        rig.hub.appDidBecomeActive()
        background.join()

        assertEquals(1, sleeper.cancelled, "coming back cancels the grace")
        assertEquals(1, a.connectCount)
        assertEquals(1, a.liveSessionCount)
        assertEquals(MachineLinkState.Online, model(rig.hub, a)?.state)
    } }

    /**
     * Grace runs out, the closing of one Mac hangs; meanwhile the app returns and the hub is stopped (a 401 or a
     * sign-out). When the closing ends, nothing may connect again.
     */
    @Test fun stopAllWhileSuspendingStartsNothing() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        val b = FakeMac("Mac mini", backgroundScope)
        val gate = Gate()
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a, b), sleeper = sleeper, connector = { GatedConnector(it, setOf(b.machine.machineId), gate) })
        rig.hub.start()
        assertTrue(eventually { model(rig.hub, a)?.state == MachineLinkState.Online && gate.waiting == 1 })

        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        eventually { sleeper.waiting == listOf(MachineHub.BACKGROUND_GRACE) }
        sleeper.release()
        // Suspending: every connection is detached, and closing Mac mini's hangs on the gate.
        assertTrue(eventually { rig.hub.connectionCount == 0 })

        rig.hub.appDidBecomeActive()
        val stopping = backgroundScope.launch { rig.hub.stopAll() }
        assertTrue(eventually { rig.hub.connectionCount == 0 })
        gate.open()
        stopping.join()
        background.join()

        assertEquals(0, rig.hub.connectionCount, "a stopped hub never reconnects")
    } }

    /** The network path changed while a Mac was still syncing (connected, snapshot not back): that attempt is replaced too. */
    @Test fun pathChangeAbortsAttemptStillSyncing() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.addPending(pendingItem("a1"))
        a.holdSnapshots()
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a), sleeper = sleeper)
        rig.hub.start()
        assertTrue(eventually { a.heldSnapshotCount == 1 })

        rig.hub.networkChanged()

        assertTrue(eventually(timeout = 3.seconds) { a.connectCount == 2 }, "the attempt on the old path was dropped")
        a.releaseSnapshots()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) })
        assertEquals(emptyList(), sleeper.requested, "no backoff for a path change")
    } }

    /** The background time ends before the grace (or none was granted): sessions close at once, and coming back
     *  reconnects from scratch. */
    @Test fun backgroundExpiryClosesAtOnce() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.addPending(pendingItem("a1"))
        val sleeper = ManualSleeper()
        val rig = hubRig(listOf(a), sleeper = sleeper)
        rig.hub.start()
        eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 1 }

        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        eventually { sleeper.waiting == listOf(MachineHub.BACKGROUND_GRACE) }

        rig.hub.backgroundTimeExpired()

        // Synchronous: nothing on screen stays actionable, even if the app is frozen right now.
        assertEquals(0, rig.hub.connectionCount)
        assertEquals(MachineLinkState.Reconnecting, model(rig.hub, a)?.state)
        assertEquals(listOf(false), rig.hub.pendingItems.map { it.actionable })
        val graceCut = eventually(timeout = 2.seconds) { sleeper.cancelled == 1 }
        assertTrue(graceCut, "the grace was cut short")
        if (!graceCut) sleeper.release()
        background.join()
        assertTrue(eventually { a.liveSessionCount == 0 })

        rig.hub.appDidBecomeActive()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) })
        assertEquals(2, a.connectCount)

        // No background time at all: close at once, without a grace.
        rig.hub.backgroundTimeExpired()
        assertEquals(0, rig.hub.connectionCount)
        rig.hub.appDidBecomeActive()
        assertTrue(eventually { allOnline(rig.hub) })
        assertEquals(3, a.connectCount)
        assertEquals(listOf(MachineHub.BACKGROUND_GRACE), sleeper.requested)
    } }

    // Teardown that outlives its caller (review 2 m-1)

    /**
     * Two Macs whose connects hang on a gate that ignores cancellation, so stopping either of them hangs too, and a third
     * Mac that is online. Whatever order the hub stops them in, some connection comes after a hanging one.
     */
    private suspend fun TestScope.teardownRig(): Triple<HubRig, FakeMac, Gate> {
        val first = FakeMac("MacBook Pro", backgroundScope)
        val second = FakeMac("Mac Studio", backgroundScope)
        val online = FakeMac("Mac mini", backgroundScope)
        val gate = Gate()
        val gated = setOf(first.machine.machineId, second.machine.machineId)
        val rig = hubRig(listOf(first, second, online), connector = { GatedConnector(it, gated, gate) })
        rig.hub.start()
        assertTrue(eventually { model(rig.hub, online)?.state == MachineLinkState.Online && gate.waiting == 2 })
        return Triple(rig, online, gate)
    }

    @Test fun aCancelledBackgroundCallerStillStopsEveryConnection() { runTest {
        val (rig, online, gate) = teardownRig()
        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
        rig.backoff.release()
        assertTrue(eventually { rig.hub.connectionCount == 0 })
        runCurrent()

        // 3D's ON_STOP job is cancelled while a close hangs.
        background.cancel()
        gate.open()

        assertTrue(eventually { online.liveSessionCount == 0 }, "Mac mini's session was closed all the same")
        assertFalse(eventually(timeout = 1.seconds) { rig.backoff.waiting.isNotEmpty() }, "no detached connection keeps trying")
        rig.hub.appDidBecomeActive()
        assertTrue(eventually { online.connectCount == 2 && model(rig.hub, online)?.state == MachineLinkState.Online })
        assertEquals(1, online.liveSessionCount, "one session per Mac after the return")
    } }

    @Test fun aCancelledStopAllStillStopsEveryConnection() { runTest {
        val (rig, online, gate) = teardownRig()
        val updates = rig.hub.chatUpdates()
        val reader = backgroundScope.launch { updates.collect {} }
        val stopping = backgroundScope.launch { rig.hub.stopAll() }
        assertTrue(eventually { rig.hub.connectionCount == 0 })
        runCurrent()

        stopping.cancel()
        gate.open()

        assertTrue(eventually { online.liveSessionCount == 0 }, "Mac mini's session was closed all the same")
        assertFalse(eventually(timeout = 1.seconds) { rig.backoff.waiting.isNotEmpty() }, "no detached connection keeps trying")
        assertTrue(eventually { reader.isCompleted }, "the update flows completed")
        assertFalse(rig.hub.scope.isActive, "the hub's scope ended")
    } }

    // Android: frozen and dozing returns (Review Focus 2, ledger A-7)

    @Test fun aReturnAfterTheGraceReconnectsEvenWhenTheTimerNeverRan() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope); a.addPending(pendingItem("a1"))
        val rig = hubRig(listOf(a)); rig.hub.start()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 1 })
        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
        rig.clock.advance(26.seconds)                    // frozen: the grace's own timer never fired
        rig.hub.appDidBecomeActive()
        assertTrue(eventually { a.connectCount == 2 && allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) })
        assertTrue(eventually { a.liveSessionCount == 1 })
        background.join()
    } }

    @Test fun aReturnWithinTheGraceByTheClockKeepsTheSessions() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope); val rig = hubRig(listOf(a)); rig.hub.start()
        assertTrue(eventually { allOnline(rig.hub) })
        val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
        rig.clock.advance(24.seconds); rig.hub.appDidBecomeActive(); background.join()
        assertEquals(1, a.connectCount); assertEquals(1, a.liveSessionCount); assertEquals(1, rig.backoff.cancelled)
    } }

    /**
     * Android (3B M-3): the Link client's liveness timers do not count deep sleep, so after a short sleep a session that
     * died meanwhile can look alive for most of a minute. A return within the grace therefore probes each online
     * session: one that answers stays, one that does not is replaced, with no backoff.
     */
    @Test fun aQuickReturnProbesEachSessionAndReplacesOneThatStoppedAnswering() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.addPending(pendingItem("a1"))
        val rig = hubRig(listOf(a))
        rig.hub.start()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 1 })
        assertEquals(1, a.snapshotCount)

        // A session that answers the probe stays.
        var background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
        rig.clock.advance(10.seconds)
        rig.hub.appDidBecomeActive()
        background.join()
        assertTrue(eventually { a.snapshotCount == 2 }, "the probe reached the Mac")
        assertEquals(1, a.connectCount)

        // A session that stopped answering while the phone slept is replaced.
        background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
        assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
        a.holdSnapshots()
        rig.clock.advance(10.seconds)
        rig.hub.appDidBecomeActive()
        background.join()
        assertTrue(eventually(timeout = 30.seconds) { a.connectCount == 2 }, "the silent session was replaced")
        a.releaseSnapshots()
        assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) })
        assertTrue(eventually { a.liveSessionCount == 1 })
        assertEquals(List(2) { MachineHub.BACKGROUND_GRACE }, rig.backoff.requested, "replacing it is not a failure: no backoff")
    } }
}
