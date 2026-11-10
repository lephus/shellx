package com.shellx.link.core

import com.shellx.link.core.LinkMessage as M
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking

/**
 * Plan 3G Task 4b at the client: a terminal flood that nobody reads stays bounded, a call answered behind it and a host
 * ping still go through at once, and the frames dropped become one resync.
 */
class LinkClientTerminalFloodTest {
    private val palette = TerminalPalette("#d0d0d0", "#101010", colors = (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })
    private val snap = TerminalFramePart(
        1,
        head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 1, cursor = TerminalCursor(0, 0), palette = palette),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "$")))),
    )

    private fun delta(revision: Long) = TerminalFramePart(
        revision,
        head = TerminalFrameHead(TerminalFrameKind.DELTA, 80, 1, cursor = TerminalCursor(0, 0), history = 25, scroll = 26),
        lines = (-25..0).map { TerminalLine(it, listOf(TerminalRun(text = "y".repeat(79)))) },
    )

    @Test
    fun aReplyBehindAnUnreadFloodArrivesAndTheFloodBecomesOneResync() {
        runBlocking {
            within(30.seconds) {
                val rig = HostRig(features = listOf(ShellXLink.TERMINAL_VIEW_FEATURE, ShellXLink.TERMINAL_CREATE_FEATURE))
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val open = async { client.openTerminalView("t-1", 80, 1) }
                val request = ch.request() as M.TerminalViewOpen
                ch.send(M.TerminalViewOpenResult(request.callId, TerminalViewOpenOutcome.OK))
                assertEquals(TerminalViewOpenOutcome.OK, open.await())

                // About 6 MB of output that nobody reads, then the answer to a call and a ping.
                val created = async { client.createTerminal("ws-1") }
                val create = ch.request() as M.TerminalCreate
                ch.send(M.TerminalViewFrame("t-1", snap))
                for (r in 2L..2_001L) ch.send(M.TerminalViewFrame("t-1", delta(r)))
                ch.send(M.TerminalCreateResult(create.callId, WorkspaceControlOutcome.OK, "t-9"))
                ch.send(M.Ping(7u))
                assertEquals(TerminalCreated(WorkspaceControlOutcome.OK, "t-9"), created.await())
                assertEquals(M.Pong(7u), ch.request { it is M.Pong })
                assertTrue(client.terminalQueuedWeight <= TerminalPushQueue.MAX_QUEUED_WEIGHT, "${client.terminalQueuedWeight}")

                val pushes = client.terminalPushes
                assertEquals(Opened("t-1"), pushes.first())
                val assembler = TerminalFrameAssembler()
                var resyncs = 0
                var lost = false
                while (!lost) {
                    val part = (pushes.first() as Frame).part
                    if (assembler.receive(part).resync) resyncs++
                    lost = part == TerminalFramePart.LOST
                }
                assertEquals(1, resyncs)
                // The host's snapshot after the resync is the next push: nothing else is left of the flood.
                ch.send(M.TerminalViewFrame("t-1", snap.copy(revision = 3_000)))
                assertEquals(listOf<TerminalViewPush>(Frame("t-1", snap.copy(revision = 3_000))), pushes.take(1).toList())
                client.close()
            }
        }
    }
}

/** The next frame from the client that [accept] takes, skipping the others (pings included). */
private suspend fun SecureChannel.request(accept: (M) -> Boolean): M {
    while (true) {
        val message = receive()
        if (accept(message)) return message
    }
}
