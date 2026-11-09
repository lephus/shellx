package com.shellx.core.demo

import com.shellx.core.testing.TerminalPushReader
import com.shellx.core.testing.eventually
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkSession
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalKey
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalModifier
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewEndReason
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import com.shellx.link.core.WorkspaceControlOutcome
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest

/** [FakeMac]'s terminals, through the session it serves a phone: views, typing into the fake shell, creation. */
class FakeMacTerminalsTest {
    private val phone = NoiseStaticKey.generate()

    private suspend fun connect(mac: FakeMac): LinkSession = mac.connector { phone }.connect(mac.machine)

    private fun ws(vararg ids: String) = LinkWorkspace(
        workspaceId = "ws-a", title = "a", order = 0,
        terminals = ids.mapIndexed { index, id -> LinkTerminal(id, id, index, selected = index == 0) },
    )

    private fun size(id: String, cols: Int, rows: Int) = FakeMac.TerminalViewSize(id, cols, rows)

    @Test fun welcomeOffersTerminalViewsAndCreation() { runTest {
        val both = setOf(ShellXLink.TERMINAL_VIEW_FEATURE, ShellXLink.TERMINAL_CREATE_FEATURE)
        assertTrue(connect(FakeMac("Mac", backgroundScope)).hostFeatures.containsAll(both))
        val old = connect(FakeMac("Old", backgroundScope, servesTerminalViews = false, acceptsTerminalCreate = false))
        assertTrue(old.hostFeatures.intersect(both).isEmpty())
    } }

    @Test fun openServesTheFixturesScreen() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        mac.setTerminalFixtures(mapOf("t1" to DemoTerminalScreens.SHELL))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        assertEquals(TerminalViewOpenOutcome.OK, session.openTerminalView("t1", 50, 40))
        val expected = TerminalScreen()
        expected.apply(DemoTerminalScreens.SHELL.snapshot)
        assertTrue(eventually {
            reader.screen.screenText() == expected.screenText() && reader.screen.historyText() == expected.historyText()
        })
        assertEquals(listOf(size("t1", 50, 40)), mac.terminalViewOpens)
    } }

    @Test fun anUnlistedTerminalIsNotFound() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        assertEquals(TerminalViewOpenOutcome.NOT_FOUND, connect(mac).openTerminalView("nope", 50, 40))
    } }

    @Test fun typingEchoesOnThePromptLine() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 5)
        session.sendTerminalInput("t1", listOf(Text("ls")))
        session.sendTerminalInput("t1", listOf(Key(TerminalKey.ENTER)))
        session.sendTerminalInput("t1", listOf(Text("x"), Key(TerminalKey.BACKSPACE)))
        session.sendTerminalInput("t1", listOf(Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))))
        assertTrue(eventually { reader.screen.screenText().take(3) == listOf("$ ls", "$ ^C", "$") }, "${reader.screen.screenText()}")
        assertEquals(4, mac.terminalViewInputs("t1").size)
    } }

    @Test fun closeResizeAndSnapshotRequestsAreRecorded() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 5)
        assertTrue(eventually { reader.screen.screenText().firstOrNull() == "$" })
        session.resizeTerminalView("t1", 30, 10)
        session.resyncTerminalView("t1")
        session.closeTerminalView("t1")
        assertTrue(eventually {
            mac.terminalViewResizes == listOf(size("t1", 30, 10)) && mac.terminalViewSnapshotRequests("t1") == 1 &&
                mac.terminalViewCloses == listOf("t1")
        })
    } }

    @Test fun createAddsATerminalTabToTheWorkspace() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        val created = session.createTerminal("ws-a")
        assertEquals(WorkspaceControlOutcome.OK, created.outcome)
        val id = assertNotNull(created.terminalId)
        assertEquals("ws-a-new-1", id)
        val added = session.workspaces().workspaces.first().terminals.firstOrNull { it.terminalId == id }
        assertNotNull(added)
        assertEquals(1, added.order)
        assertEquals(false, added.selected)
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, session.createTerminal("nope").outcome)
        mac.setNextTerminalCreateOutcome(WorkspaceControlOutcome.REFUSED)
        val refused = session.createTerminal("ws-a")
        assertEquals(WorkspaceControlOutcome.REFUSED, refused.outcome)
        assertNull(refused.terminalId)
        assertEquals(listOf("ws-a", "nope", "ws-a"), mac.terminalCreates)
    } }

    @Test fun emittedFramesAndEndsReachThePhone() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 5)
        assertTrue(eventually { reader.screen.screenText().firstOrNull() == "$" })
        mac.emitTerminalFrame(
            "t1",
            TerminalGridFrame(
                TerminalFrameHead(TerminalFrameKind.DELTA, 20, 5, cursor = TerminalCursor(0, 0)),
                lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "hi")))),
            ),
        )
        assertTrue(eventually { reader.screen.screenText().firstOrNull() == "hi" }, "${reader.screen.screenText()}")
        mac.endTerminalView("t1", TerminalViewEndReason.GONE)
        assertTrue(eventually { Ended("t1", TerminalViewEndReason.GONE) in reader.pushes })
    } }

    @Test fun refusedAndHeldOpens() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1", "t2")))
        val session = connect(mac)
        mac.refuseTerminalView("t1", TerminalViewOpenOutcome.REFUSED)
        assertEquals(TerminalViewOpenOutcome.REFUSED, session.openTerminalView("t1", 20, 5))
        mac.holdTerminalViewOpens()
        val pending = backgroundScope.async { session.openTerminalView("t2", 20, 5) }
        assertTrue(eventually { mac.terminalViewOpens.size == 2 })
        mac.releaseTerminalViewOpens()
        assertEquals(TerminalViewOpenOutcome.OK, pending.await())
    } }

    @Test fun ticksAppendLinesWhileTheTerminalIsViewed() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val ticking = DemoTerminalFixture(
            cols = 20, rows = 3, screen = emptyList(), cursor = TerminalCursor(0, 0),
            ticks = listOf(DemoTerminalScreens.runs("tick")), tickInterval = 20.milliseconds,
        )
        mac.setTerminalFixtures(mapOf("t1" to ticking))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 3)
        assertTrue(eventually { reader.screen.screenText().take(2) == listOf("tick", "tick") }, "${reader.screen.screenText()}")
    } }

    @Test fun anotherTerminalIsBusyAndTheSameOneRestarts() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1", "t2")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        assertEquals(TerminalViewOpenOutcome.OK, session.openTerminalView("t1", 20, 5))
        assertEquals(TerminalViewOpenOutcome.BUSY, session.openTerminalView("t2", 20, 5))
        assertEquals(listOf(size("t1", 20, 5)), mac.terminalViewOpens)
        assertEquals(TerminalViewOpenOutcome.OK, session.openTerminalView("t1", 20, 5))
        assertEquals(listOf("t1"), mac.terminalViewCloses)
        assertTrue(eventually { reader.pushes.count { it == Opened("t1") } == 2 && reader.pushes.last() is Frame })
        val newest = reader.pushes.drop(reader.pushes.lastIndexOf(Opened("t1")) + 1)
        assertEquals(1L, assertIs<Frame>(newest.first()).part.revision)
    } }

    @Test fun openedComesBeforeTheFirstFrame() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 5)
        assertTrue(eventually { reader.pushes.size >= 2 })
        assertEquals(Opened("t1"), reader.pushes[0])
        val first = assertIs<Frame>(reader.pushes[1])
        assertEquals("t1", first.terminalId)
        assertEquals(1L, first.part.revision)
        assertEquals(TerminalFrameKind.SNAPSHOT, first.part.head?.kind)
    } }

    @Test fun sizesAreClampedAndNonPositiveOnesRefused() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1")))
        val session = connect(mac)
        session.openTerminalView("t1", 10, 2)
        assertEquals(listOf(size("t1", 20, 5)), mac.terminalViewOpens)
        session.resizeTerminalView("t1", 999, 999)
        assertTrue(eventually { mac.terminalViewResizes == listOf(size("t1", 300, 120)) }, "${mac.terminalViewResizes}")
        val refused = assertFailsWith<LinkClientException.Remote> { session.openTerminalView("t1", 0, 24) }
        assertEquals("bad_request", refused.code)
    } }

    @Test fun inputResizeAndResyncOfAnotherTerminalAreNotOpen() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1", "t2")))
        val session = connect(mac)
        val reader = TerminalPushReader(session.terminalPushes, "t1", backgroundScope)
        session.openTerminalView("t1", 20, 5)
        session.sendTerminalInput("t2", listOf(Text("x")))
        session.resizeTerminalView("t2", 30, 10)
        session.resyncTerminalView("t2")
        val notOpen = Ended("t2", TerminalViewEndReason.NOT_OPEN)
        assertTrue(eventually { reader.pushes.count { it == notOpen } == 3 }, "${reader.pushes}")
        assertEquals(emptyList(), mac.terminalViewInputs("t2"))
        assertEquals(0, mac.terminalViewSnapshotRequests("t2"))
    } }

    @Test fun sessionEndClosesTheView() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        mac.setWorkspaces(listOf(ws("t1", "t2")))
        val first = connect(mac)
        val second = connect(mac)
        first.openTerminalView("t1", 20, 5)
        second.openTerminalView("t2", 20, 5)
        first.close()
        assertTrue(eventually { mac.terminalViewCloses == listOf("t1") }, "${mac.terminalViewCloses}")
        mac.dropLiveSessions()
        assertTrue(eventually { mac.terminalViewCloses == listOf("t1", "t2") }, "${mac.terminalViewCloses}")
    } }
}
