package com.shellx.core.terminal

import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalViewOpenOutcome
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * The terminal view model through a real [com.shellx.core.link.MachineHub] and a [FakeMac] whose `ws-a` holds `t1` and
 * `t2` (TerminalViewLiveTests.swift). The fake's input, resize, resync and close return before the Mac acts on them, so
 * every check on what the Mac got waits for it.
 */
class TerminalViewLiveTest {
    private fun TestScope.makeMac(): FakeMac {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(
            listOf(linkWorkspace("a", terminals = listOf(linkTerminal("t1", selected = true), linkTerminal("t2", order = 1)))),
        )
        return mac
    }

    /** A model of [mac] through `rig.hub`, its outbox and delays in the hub's scope, running until the test ends. */
    private fun TestScope.makeModel(mac: FakeMac, rig: HubRig): TerminalViewModel {
        val model = TerminalViewModel(mac.machine.machineId, rig.hub, rig.hub.scope)
        backgroundScope.launch { model.run() }
        return model
    }

    @Test fun opensSwitchesAndClosesThroughAFakeMac() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = makeModel(mac, rig)
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(
            eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText().firstOrNull() == "$" },
            "${model.phase} ${model.screen.screenText()}",
        )
        assertEquals(listOf(FakeMac.TerminalViewSize("t1", 30, 6)), mac.terminalViewOpens)
        model.show("t2")
        assertTrue(eventually {
            model.phase == TerminalViewPhase.Live && mac.terminalViewCloses == listOf("t1") &&
                mac.terminalViewOpens.map { it.terminalId } == listOf("t1", "t2")
        }, "closed before the next open: no busy, no retry")
        model.show(null)
        assertTrue(eventually { mac.terminalViewCloses == listOf("t1", "t2") })
    } }

    @Test fun aReconnectReopensTheView() { runTest {   // Review Focus 4
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = makeModel(mac, rig)
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText().firstOrNull() == "$" })
        mac.dropLiveSessions()
        assertTrue(eventually {
            rig.backoff.release()
            model.phase == TerminalViewPhase.Live && mac.terminalViewOpens.size == 2
        }, "${model.phase}")
    } }

    @Test fun aTerminalTheMacCannotViewFailsLikeAnyFailure() { runTest {   // contracts §17
        val mac = makeMac()
        mac.refuseTerminalView("t1", TerminalViewOpenOutcome.FAILED)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = makeModel(mac, rig)
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually {
            model.phase == TerminalViewPhase.Unavailable(TerminalUnavailableReason.FAILED) && mac.terminalViewOpens.size == 2
        }, "one retry after 1 s, then Try Again")
    } }

    @Test fun typingEchoesThroughAFakeMac() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = makeModel(mac, rig)
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText().firstOrNull() == "$" })
        model.insertText("ls"); model.press(TerminalKey.ENTER)
        assertTrue(eventually { model.screen.screenText().take(2) == listOf("$ ls", "$") }, "${model.screen.screenText()}")
        assertEquals(listOf(listOf(Text("ls")), listOf(Key(TerminalKey.ENTER))), mac.terminalViewInputs("t1"))
    } }

    /** Review Focus 1, A → B → A through a real hub and fake Mac: the keys typed after the last swipe reach A only (the
     *  iPhone's final review, core M8). */
    @Test fun swipingBackAndForthTypesIntoTheTerminalShown() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = makeModel(mac, rig)
        model.setPhoneGrid(30, 6)
        model.show("t1"); model.show("t2"); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live && model.terminalId == "t1" }, "${model.phase}")
        model.insertText("ab")
        assertTrue(eventually { mac.terminalViewInputs("t1") == listOf(listOf(Text("ab"))) })
        assertEquals(emptyList(), mac.terminalViewInputs("t2"))
    } }

    /**
     * Review C I-1, end to end: with the hub, the fake Mac and the page all on an immediate dispatcher (the demo on the
     * app's `Main.immediate`), the Mac's answer, `Opened` and first screen are handled inside the open's send. The page
     * stays live, with one first-screen sample.
     */
    @Test fun onAnImmediateDispatcherTheFirstScreenStaysLive() { runTest {
        val immediate = CoroutineScope(backgroundScope.coroutineContext + UnconfinedTestDispatcher(testScheduler))
        val mac = FakeMac("Mac", immediate)
        mac.setWorkspaces(listOf(linkWorkspace("a", terminals = listOf(linkTerminal("t1", selected = true)))))
        val rig = hubRig(listOf(mac), start = true, scope = immediate)
        assertTrue(rig.online(sessions = 0))
        val model = TerminalViewModel(mac.machine.machineId, rig.hub, rig.hub.scope)
        immediate.launch { model.run() }
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live }, "${model.phase}")
        delay(50.milliseconds)
        assertEquals(TerminalViewPhase.Live, model.phase)
        assertEquals(1, rig.latency.summary(LatencyMetric.TERMINAL_FIRST_SCREEN)?.count)
    } }

    /**
     * Re-review B N-1: a run stopped while its open waits leaves no `Opened` behind, so the next run of the same
     * terminal shows only its own view's screen. The model's outbox runs on an immediate dispatcher, as on the app's
     * `Main.immediate`: the next run's open is on its way before that run takes what the queue kept.
     */
    @Test fun aRunCancelledWhileConnectingLeavesNoScreenForTheNextRun() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        mac.holdTerminalViewOpens()
        val immediate = CoroutineScope(rig.hub.scope.coroutineContext + UnconfinedTestDispatcher(testScheduler))
        val model = TerminalViewModel(mac.machine.machineId, rig.hub, immediate)
        val first = backgroundScope.launch { model.run() }
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { mac.terminalViewOpens.size == 1 })

        first.cancel()
        runCurrent()
        mac.releaseTerminalViewOpens()
        runCurrent()
        model.setPhoneGrid(40, 8)
        backgroundScope.launch { model.run() }

        assertTrue(
            eventually { model.phase == TerminalViewPhase.Live && model.screen.cols == 40 },
            "${model.phase} ${model.screen.cols}",
        )
        assertEquals(1, model.snapshots, "the first view's snapshot never showed")
        assertEquals(1, rig.latency.summary(LatencyMetric.TERMINAL_FIRST_SCREEN)?.count)
        assertEquals(listOf(30, 40), mac.terminalViewOpens.map { it.cols })
    } }

    /**
     * Review C m1: an open still queued behind another message when the page stops (a swipe, then the background, within
     * one round trip) never goes out, so its `Opened` cannot wait in the queue for the next run either.
     */
    @Test fun aStoppedPageSendsNoOpenItHadQueued() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        mac.holdTerminalViewOpens()
        val immediate = CoroutineScope(rig.hub.scope.coroutineContext + UnconfinedTestDispatcher(testScheduler))
        val model = TerminalViewModel(mac.machine.machineId, rig.hub, immediate)
        val first = backgroundScope.launch { model.run() }
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { mac.terminalViewOpens.size == 1 })
        model.show("t2")

        first.cancel()
        runCurrent()
        mac.releaseTerminalViewOpens()
        runCurrent()
        model.setPhoneGrid(40, 8)
        backgroundScope.launch { model.run() }

        assertTrue(
            eventually { model.phase == TerminalViewPhase.Live && model.screen.cols == 40 },
            "${model.phase} ${model.screen.cols}",
        )
        assertEquals(1, model.snapshots, "no screen of the open the stopped page had queued")
        assertEquals(listOf("t1" to 30, "t2" to 40), mac.terminalViewOpens.map { it.terminalId to it.cols })
    } }

    private fun row0(text: String) = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.DELTA, 30, 6, cursor = TerminalCursor(0, 0)),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = text)))),
    )

    /**
     * Final review m8 (b): a run stopped and started in one turn (a rotation, the background and back) keeps the screen
     * meanwhile, takes every push after it, and asks for one resync at most: nothing buffers pushes before the model's
     * assembler, where a cancel would lose them.
     */
    @Test fun aRestartedRunKeepsTheScreenAndResyncsAtMostOnce() { runTest {
        val mac = makeMac()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(sessions = 0))
        val model = TerminalViewModel(mac.machine.machineId, rig.hub, rig.hub.scope)
        var run = backgroundScope.launch { model.run() }
        model.setPhoneGrid(30, 6); model.show("t1")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live && model.screen.screenText().firstOrNull() == "$" })
        repeat(5) { mac.emitTerminalFrame("t1", row0("a$it")) }
        assertTrue(eventually { model.screen.screenText().firstOrNull() == "a4" }, "${model.screen.screenText()}")
        run.cancel()
        run = backgroundScope.launch { model.run() }
        assertEquals("a4", model.screen.screenText().first(), "the screen stays")
        assertTrue(eventually { model.phase == TerminalViewPhase.Live })
        mac.emitTerminalFrame("t1", row0("after"))
        assertTrue(eventually { model.screen.screenText().firstOrNull() == "after" }, "${model.screen.screenText()}")
        delay(50.milliseconds)
        assertTrue(mac.terminalViewSnapshotRequests("t1") <= 1, "${mac.terminalViewSnapshotRequests("t1")} resyncs")
        run.cancel()
    } }
}
