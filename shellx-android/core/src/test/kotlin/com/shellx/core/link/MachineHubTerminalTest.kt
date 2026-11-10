package com.shellx.core.link

import com.shellx.core.demo.FakeMac
import com.shellx.core.terminal.TerminalHubEvent
import com.shellx.core.terminal.TerminalOpenResult
import com.shellx.core.testing.Collector
import com.shellx.core.testing.Gate
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameAssembler
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import com.shellx.link.core.WorkspaceControlOutcome
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** The hub's terminal calls and events ([com.shellx.core.terminal.TerminalLink], `createTerminal`), against a FakeMac. */
class MachineHubTerminalTest {
    /** A Mac with `ws-a` holding `t1` and `t2`. */
    private fun TestScope.makeMac(
        name: String = "Mac",
        servesTerminalViews: Boolean = true,
        acceptsTerminalCreate: Boolean = true,
    ): FakeMac {
        val mac = FakeMac(
            name, backgroundScope, servesTerminalViews = servesTerminalViews, acceptsTerminalCreate = acceptsTerminalCreate,
        )
        mac.setWorkspaces(
            listOf(linkWorkspace("a", terminals = listOf(linkTerminal("t1", selected = true), linkTerminal("t2", order = 1)))),
        )
        return mac
    }

    private val ok = TerminalOpenResult.Outcome(TerminalViewOpenOutcome.OK)

    @Test fun hubOffersTerminalsOnlyWhenTheMacDoes() { runTest {
        val mac = makeMac()
        val old = makeMac(name = "Old", servesTerminalViews = false, acceptsTerminalCreate = false)
        val rig = hubRig(listOf(mac, old), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val oldId = old.machine.machineId

        assertTrue(rig.hub.isOnline(id))
        assertTrue(rig.hub.supportsTerminalView(id))
        assertTrue(rig.hub.supportsTerminalCreate(id))
        assertTrue(rig.hub.isOnline(oldId))
        assertFalse(rig.hub.supportsTerminalView(oldId))
        assertFalse(rig.hub.supportsTerminalCreate(oldId))
    } }

    @Test fun pushesArriveInOrderAfterTheOpen() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val events = Collector(rig.hub.terminalEvents(id), backgroundScope)
        runCurrent()

        val answer = rig.hub.openTerminalView(id, "t1", 50, 20)

        assertEquals(ok, answer)
        fun pushes() = events.items.mapNotNull { (it as? TerminalHubEvent.Push)?.takeIf { e -> e.machineId == id }?.push }
        assertTrue(eventually { pushes().any { it is Frame && it.terminalId == "t1" } })
        assertEquals(Opened("t1"), pushes().first())
        assertEquals(listOf(FakeMac.TerminalViewSize("t1", 50, 20)), mac.terminalViewOpens)
    } }

    @Test fun inputResizeResyncAndCloseReachTheMac() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId

        rig.hub.openTerminalView(id, "t1", 50, 20)
        rig.hub.sendTerminalInput(id, "t1", listOf(Text("ls")))
        rig.hub.resizeTerminalView(id, "t1", 60, 30)
        rig.hub.resyncTerminalView(id, "t1")
        rig.hub.closeTerminalView(id, "t1")

        assertTrue(eventually {
            mac.terminalViewInputs("t1") == listOf(listOf(Text("ls"))) && mac.terminalViewCloses == listOf("t1") &&
                mac.terminalViewSnapshotRequests("t1") == 1 &&
                mac.terminalViewResizes == listOf(FakeMac.TerminalViewSize("t1", 60, 30))
        })
    } }

    @Test fun nothingIsSentWithoutTheFeature() { runTest {
        val mac = makeMac(servesTerminalViews = false, acceptsTerminalCreate = false)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val before = mac.phoneCallCount

        assertEquals(TerminalOpenResult.NotSent, rig.hub.openTerminalView(id, "t1", 50, 20))
        rig.hub.sendTerminalInput(id, "t1", listOf(Text("x")))
        rig.hub.resizeTerminalView(id, "t1", 60, 30)
        rig.hub.resyncTerminalView(id, "t1")
        rig.hub.closeTerminalView(id, "t1")
        val made = rig.hub.createTerminal(WorkspaceRef(id, "ws-a"))

        assertEquals(WorkspaceCommandResult.Failed, made.result)
        assertNull(made.terminalId)
        assertEquals(before, mac.phoneCallCount)
    } }

    @Test fun nothingIsSentToAMacThatIsNotOnline() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))

        assertFalse(rig.hub.isOnline("mac-nope"))
        assertFalse(rig.hub.supportsTerminalView("mac-nope"))
        assertEquals(TerminalOpenResult.NotSent, rig.hub.openTerminalView("mac-nope", "t1", 50, 20))
        val made = rig.hub.createTerminal(WorkspaceRef("mac-nope", "ws-a"))
        assertEquals(WorkspaceCommandResult.Offline, made.result)
        assertNull(made.terminalId)
    } }

    @Test fun stateChangesReachTerminalSubscribers() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val events = Collector(rig.hub.terminalEvents(id), backgroundScope)
        runCurrent()

        mac.dropLiveSessions()

        assertTrue(eventually {
            rig.backoff.release()
            val states = events.items.mapNotNull { (it as? TerminalHubEvent.State)?.takeIf { e -> e.machineId == id }?.state }
            MachineLinkState.Reconnecting in states && states.lastOrNull() == MachineLinkState.Online
        }, "${events.items}")
    } }

    @Test fun createTerminalOutcomes() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId

        val made = rig.hub.createTerminal(WorkspaceRef(id, "ws-a"))
        assertEquals(WorkspaceCommandResult.Ok(null), made.result)
        val newId = assertNotNull(made.terminalId)
        assertTrue(eventually {
            rig.hub.machines.first().workspaces.workspace("ws-a")?.terminals?.any { it.terminalId == newId } == true
        })

        val missing = rig.hub.createTerminal(WorkspaceRef(id, "nope"))
        assertEquals(WorkspaceCommandResult.NotFound, missing.result)
        assertNull(missing.terminalId)

        mac.setNextTerminalCreateOutcome(WorkspaceControlOutcome.REFUSED)
        val refused = rig.hub.createTerminal(WorkspaceRef(id, "ws-a"))
        assertEquals(WorkspaceCommandResult.Refused, refused.result)
        assertNull(refused.terminalId)

        assertEquals(listOf("ws-a", "nope", "ws-a"), mac.terminalCreates)
    } }

    @Test fun stopAllFinishesTheTerminalStream() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val finished = backgroundScope.async {
            rig.hub.terminalEvents(mac.machine.machineId).collect {}
            true
        }
        runCurrent()
        assertEquals(1, rig.hub.terminalSubscriberCount)

        rig.hub.stopAll()

        assertTrue(finished.await())
        assertEquals(0, rig.hub.terminalSubscriberCount)
    } }

    // Plan 3G Decision 1: the pushes go from the session's bounded queue straight to the page's assembler.

    /**
     * A terminal flood while the page is busy stays in the session's bounded queue: the page gets a small part of it,
     * then the queue's LOST part, asks for one resync, and the Mac's snapshot mends the screen. The flood comes in
     * batches with the dispatcher run between them, as a reader thread delivers it: a hub that re-buffered the pushes
     * (an unbounded channel filled by the connection, or a `buffer` before the page) would drain the queue each time
     * and hand the page all 20 000 frames.
     */
    @Test fun aFloodThroughTheHubIsBoundedAndCostsOneResync() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val view = HubView(rig.hub, id, "t1", backgroundScope)
        view.start()
        runCurrent()
        assertEquals(ok, rig.hub.openTerminalView(id, "t1", 50, 20))
        assertTrue(eventually { view.screen.screenText().firstOrNull() == "$" })

        val gate = Gate()
        view.gate = gate
        repeat(200) {
            repeat(100) { mac.emitTerminalFrame("t1", flood) }
            runCurrent()
        }
        gate.open()

        assertTrue(eventually { view.resyncs == 1 && !view.assembler.awaitingSnapshot }, "${view.resyncs}")
        assertEquals(1, mac.terminalViewSnapshotRequests("t1"))
        assertTrue(view.frames < 2_000, "${view.frames} frames reached the page")
        assertEquals("$", view.screen.screenText().first())
    } }

    /**
     * A page whose collection stops right after it handled a push, while the next ones have arrived, and starts again
     * in the same main-loop turn (a restarted effect) loses none of them: no resync (the queue's own tests show why: a
     * cancelled collector takes nothing more). One that starts later loses none either: what came meanwhile waited in
     * the session's bounded queue.
     */
    @Test fun aRestartedCollectionLosesNoPushEarlyOrLate() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val view = HubView(rig.hub, id, "t1", backgroundScope)
        view.start()
        runCurrent()
        rig.hub.openTerminalView(id, "t1", 50, 20)
        assertTrue(eventually { view.screen.screenText().firstOrNull() == "$" })
        val before = view.frames

        view.restartAfterNextFrame = true
        repeat(3) { mac.emitTerminalFrame("t1", row0("a$it")) }
        runCurrent()

        assertTrue(eventually { view.screen.screenText().firstOrNull() == "a2" }, "${view.screen.screenText()}")
        assertEquals(before + 3, view.frames)
        assertEquals(0, view.resyncs)

        view.stop()
        runCurrent()
        mac.emitTerminalFrame("t1", row0("waited"))
        runCurrent()
        view.start()
        runCurrent()
        mac.emitTerminalFrame("t1", row0("b"))

        assertTrue(eventually { view.screen.screenText().firstOrNull() == "b" }, "${view.screen.screenText()}")
        assertEquals(before + 5, view.frames)
        assertEquals(0, view.resyncs)
        assertEquals(0, mac.terminalViewSnapshotRequests("t1"))
    } }

    /**
     * Review B1 I-1: the iPhone's order. The page asks for its events, sends the open, and collects a little later. The
     * open's `Opened` and first snapshot wait for it in the session's queue: nothing takes them away meanwhile.
     */
    @Test fun anOpenSentBeforeThePageCollectsKeepsItsFirstScreen() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        openThenCollect(rig.hub, mac.machine.machineId)
    } }

    /**
     * Review B1 I-1, as the app runs it: the hub and the fake Mac on an immediate dispatcher (the app's
     * `Dispatchers.Main.immediate`, which the demo shares with its fake Mac), where the Mac's answer, its `Opened` and
     * its snapshot all come inside the open call.
     */
    @Test fun onAnImmediateDispatcherAnOpenSentBeforeThePageCollectsKeepsItsFirstScreen() { runTest {
        val immediate = CoroutineScope(backgroundScope.coroutineContext + UnconfinedTestDispatcher(testScheduler))
        val mac = FakeMac("Mac", immediate)
        mac.setWorkspaces(listOf(linkWorkspace("a", terminals = listOf(linkTerminal("t1", selected = true)))))
        val rig = hubRig(listOf(mac), start = true, scope = immediate)
        assertTrue(rig.online(sessions = 0))
        openThenCollect(rig.hub, mac.machine.machineId)
    } }

    private suspend fun TestScope.openThenCollect(hub: MachineHub, id: String) {
        val events = hub.terminalEvents(id)
        assertEquals(ok, hub.openTerminalView(id, "t1", 50, 20))
        runCurrent()
        val view = HubView(hub, id, "t1", backgroundScope)
        view.collect(events)
        runCurrent()

        assertTrue(eventually { view.screen.screenText().firstOrNull() == "$" }, "${view.pushes}")
        assertEquals(Opened("t1"), view.pushes.first())
        val snapshot = assertIs<Frame>(view.pushes[1])
        assertEquals(TerminalFrameKind.SNAPSHOT, snapshot.part.head?.kind)
    }

    /** The newest collection of a Mac takes its pushes; an older one takes them again when the newer one ends. */
    @Test fun theNewestCollectionTakesThePushes() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val id = mac.machine.machineId
        val older = HubView(rig.hub, id, "t1", backgroundScope)
        older.start()
        runCurrent()
        rig.hub.openTerminalView(id, "t1", 50, 20)
        assertTrue(eventually { older.screen.screenText().firstOrNull() == "$" })
        val newer = mutableListOf<TerminalViewPush>()
        val newerJob = backgroundScope.launch {
            rig.hub.terminalEvents(id).collect { (it as? TerminalHubEvent.Push)?.let { e -> newer += e.push } }
        }
        runCurrent()
        assertEquals(2, rig.hub.terminalSubscriberCount)
        val olderBefore = older.pushes.size

        mac.emitTerminalFrame("t1", row0("newer"))
        assertTrue(eventually { newer.size == 1 })
        assertEquals(olderBefore, older.pushes.size)

        newerJob.cancel()
        runCurrent()
        mac.emitTerminalFrame("t1", row0("older"))
        assertTrue(eventually { older.pushes.size > olderBefore })
        assertEquals(1, newer.size)
        val revisions = (newer + older.pushes.drop(olderBefore)).mapNotNull { (it as? Frame)?.part?.revision }
        assertEquals(revisions.distinct(), revisions, "no push went to both")
    } }

    /** A delta of the 50 × 20 prompt view, every row full: about 1.8 KB of frame JSON. */
    private val flood = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.DELTA, 50, 20, cursor = TerminalCursor(0, 0)),
        lines = (0 until 20).map { TerminalLine(it, listOf(TerminalRun(text = "y".repeat(49)))) },
    )

    private fun row0(text: String) = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.DELTA, 50, 20, cursor = TerminalCursor(0, 0)),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = text)))),
    )

    /**
     * A terminal page as Task 9's model will be: it collects the hub's events for one Mac, handles each push in its
     * collector's code, keeps its assembler and screen across a stop and a start, and asks for a resync when the
     * assembler says so. [gate], when set, holds it before it handles the next push (a busy main thread).
     */
    private class HubView(
        private val hub: MachineHub,
        private val machineId: String,
        private val terminalId: String,
        private val scope: CoroutineScope,
    ) {
        var assembler = TerminalFrameAssembler()
        var screen = TerminalScreen()
        var frames = 0
        var resyncs = 0
        val pushes = mutableListOf<TerminalViewPush>()
        var gate: Gate? = null

        /** Set: right after the next frame, the collection stops and a new one starts, in the same turn. */
        var restartAfterNextFrame = false
        private var job: Job? = null

        fun start() {
            collect(hub.terminalEvents(machineId))
        }

        /** Collects [events], which the page asked for earlier. */
        fun collect(events: Flow<TerminalHubEvent>) {
            job = scope.launch { events.collect { take(it) } }
        }

        fun stop() {
            job?.cancel()
        }

        private suspend fun take(event: TerminalHubEvent) {
            if (event !is TerminalHubEvent.Push || event.machineId != machineId) return
            gate?.wait()
            val push = event.push
            pushes += push
            if (push.terminalId != terminalId) return
            when (push) {
                is Opened -> {
                    assembler = TerminalFrameAssembler()
                    screen = TerminalScreen()
                }
                is Frame -> {
                    frames += 1
                    val result = assembler.receive(push.part)
                    if (result.resync) {
                        resyncs += 1
                        scope.launch { hub.resyncTerminalView(machineId, terminalId) }
                    }
                    result.frame?.let(screen::apply)
                    if (restartAfterNextFrame) {
                        restartAfterNextFrame = false
                        stop()
                        start()
                    }
                }
                is TerminalViewPush.Ended -> Unit
            }
        }
    }
}
