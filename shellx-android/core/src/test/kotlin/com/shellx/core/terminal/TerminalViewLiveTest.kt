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
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalViewOpenOutcome
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
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
}
