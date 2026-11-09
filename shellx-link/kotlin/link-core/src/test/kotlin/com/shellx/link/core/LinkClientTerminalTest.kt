package com.shellx.link.core

import com.shellx.link.core.LinkMessage as M
import com.shellx.link.core.TerminalInputUnit.Key
import com.shellx.link.core.TerminalInputUnit.Text
import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking

/** The client side of terminal views and `terminal.create` (2A's `LinkClient`; `TerminalSessionTests`). */
class LinkClientTerminalTest {
    private val features = listOf(ShellXLink.TERMINAL_VIEW_FEATURE, ShellXLink.TERMINAL_CREATE_FEATURE)
    private val palette = TerminalPalette("#d0d0d0", "#101010", colors = (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })
    private val snap = TerminalFramePart(
        1,
        head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 20, 1, cursor = TerminalCursor(0, 0), palette = palette),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "$")))),
    )
    private val delta = TerminalFramePart(
        2,
        head = TerminalFrameHead(TerminalFrameKind.DELTA, 20, 1, cursor = TerminalCursor(4, 0)),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "$ ls")))),
    )

    @Test
    fun openAnswersOkAndOpenedComesBeforeTheFirstFrame() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val open = async { client.openTerminalView("t-1", 46, 30) }
                val request = ch.request() as M.TerminalViewOpen
                assertEquals(M.TerminalViewOpen(request.callId, "t-1", 46, 30), request)
                ch.send(M.TerminalViewOpenResult(request.callId, TerminalViewOpenOutcome.OK))
                ch.send(M.TerminalViewFrame("t-1", snap))
                assertEquals(TerminalViewOpenOutcome.OK, open.await())
                assertEquals(listOf(Opened("t-1"), Frame("t-1", snap)), client.terminalPushes.take(2).toList())
                client.close()
            }
        }
    }

    @Test
    fun anOpenThatIsNotOkYieldsNoOpened() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val outcomes = listOf(
                    TerminalViewOpenOutcome.BUSY, TerminalViewOpenOutcome.NOT_FOUND, TerminalViewOpenOutcome.REFUSED,
                    TerminalViewOpenOutcome.FAILED, TerminalViewOpenOutcome("later"),
                )
                for (outcome in outcomes) {
                    val open = async { client.openTerminalView("t-1", 46, 30) }
                    val request = ch.request() as M.TerminalViewOpen
                    ch.send(M.TerminalViewOpenResult(request.callId, outcome))
                    assertEquals(outcome, open.await())
                }
                ch.send(M.TerminalViewEnded("t-1", TerminalViewEndReason.GONE))
                assertEquals(Ended("t-1", TerminalViewEndReason.GONE), client.terminalPushes.first())
                client.close()
            }
        }
    }

    @Test
    fun openErrorsAreRemote() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val unsupported = async { assertFailsWith<LinkClientException.Remote> { client.openTerminalView("t-1", 46, 30) } }
                ch.send(M.Error("unsupported", "no views", (ch.request() as M.TerminalViewOpen).callId))
                assertEquals(LinkClientException.Remote("unsupported", "no views"), unsupported.await())
                val bad = async { assertFailsWith<LinkClientException.Remote> { client.openTerminalView("t-1", 0, 30) } }
                ch.send(M.Error("bad_request", "cols", (ch.request() as M.TerminalViewOpen).callId))
                assertEquals(LinkClientException.Remote("bad_request", "cols"), bad.await())
                client.close()
            }
        }
    }

    @Test
    fun aLateOkOfATimedOutOpenYieldsNoOpened() {
        runBlocking {
            within {
                val rig = HostRig(features = features, timings = LinkTimings(20.seconds, 45.seconds, requestTimeout = 300.milliseconds))
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val open = async { assertFailsWith<LinkClientException.TimedOut> { client.openTerminalView("t-1", 46, 30) } }
                val held = ch.request() as M.TerminalViewOpen
                open.await()
                ch.send(M.TerminalViewOpenResult(held.callId, TerminalViewOpenOutcome.OK))
                ch.send(M.TerminalViewEnded("t-1", TerminalViewEndReason.GONE))
                assertEquals(Ended("t-1", TerminalViewEndReason.GONE), client.terminalPushes.first())
                client.close()
            }
        }
    }

    @Test
    fun framesAndEndsArriveInOrder() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                ch.send(M.TerminalViewFrame("t-1", snap))
                ch.send(M.TerminalViewFrame("t-1", delta))
                ch.send(M.TerminalViewEnded("t-2", TerminalViewEndReason.NOT_OPEN))
                assertEquals(
                    listOf(Frame("t-1", snap), Frame("t-1", delta), Ended("t-2", TerminalViewEndReason.NOT_OPEN)),
                    client.terminalPushes.take(3).toList(),
                )
                client.close()
            }
        }
    }

    @Test
    fun callLessMessagesReachTheHost() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                client.closeTerminalView("t-1")
                client.resizeTerminalView("t-1", 80, 24)
                client.resyncTerminalView("t-1")
                client.sendTerminalInput("t-1", listOf(Text("ls"), Key(TerminalKey.ENTER)))
                assertEquals(
                    listOf(
                        M.TerminalViewClose("t-1"), M.TerminalViewResize("t-1", 80, 24), M.TerminalViewResync("t-1"),
                        M.TerminalViewInput("t-1", listOf(Text("ls"), Key(TerminalKey.ENTER))),
                    ),
                    List(4) { ch.request() },
                )
                client.close()
            }
        }
    }

    @Test
    fun aTypedNewlineIsRefusedBeforeSending() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val e = assertFailsWith<TerminalInputException> { client.sendTerminalInput("t-1", listOf(Text("ls\n"))) }
                assertFalse("ls" in e.reason)
                assertFalse("ls" in e.message.orEmpty())
                client.resyncTerminalView("t-1")
                assertEquals(M.TerminalViewResync("t-1"), ch.request())
                client.close()
            }
        }
    }

    @Test
    fun createTerminalUnpacksItsAnswer() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val ok = async { client.createTerminal("ws-1") }
                val first = ch.request() as M.TerminalCreate
                assertEquals(M.TerminalCreate(first.callId, "ws-1"), first)
                ch.send(M.TerminalCreateResult(first.callId, WorkspaceControlOutcome.OK, "t-9"))
                assertEquals(TerminalCreated(WorkspaceControlOutcome.OK, "t-9"), ok.await())
                val refused = async { client.createTerminal("ws-1") }
                ch.send(M.TerminalCreateResult((ch.request() as M.TerminalCreate).callId, WorkspaceControlOutcome.REFUSED))
                assertEquals(TerminalCreated(WorkspaceControlOutcome.REFUSED, null), refused.await())
                val odd = async { assertFailsWith<LinkClientException.UnexpectedAnswer> { client.createTerminal("ws-1") } }
                ch.send(M.ChatSendResult((ch.request() as M.TerminalCreate).callId, ChatSendOutcome.SUBMITTED))
                odd.await()
                client.close()
            }
        }
    }

    @Test
    fun closeCompletesTerminalPushesAndLaterSendsThrow() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                host.await()
                client.close()
                assertEquals(emptyList(), client.terminalPushes.toList())
                assertFailsWith<LinkClientException.SessionClosed> { client.closeTerminalView("t-1") }
            }
        }
    }

    @Test
    fun anUndecodableFrameIsDroppedAndTheNextArrives() {
        runBlocking {
            within {
                val rig = HostRig(features = features)
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                ch.sendFrame("""{"v":1,"t":"terminal.view.frame","terminal_id":"t-1","revision":0,"part":0,"parts":1}""".encodeToByteArray())
                ch.send(M.TerminalViewFrame("t-1", snap))
                assertEquals(Frame("t-1", snap), client.terminalPushes.first())
                client.close()
            }
        }
    }
}
