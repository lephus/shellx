package com.shellx.link.core

import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking

/** Plan 3G Task 4b: the client's terminal pushes are bounded, and frames it drops become one resync. */
class TerminalPushQueueTest {
    private val palette = TerminalPalette("#d0d0d0", "#101010", colors = (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })

    private fun snapshot(revision: Long, text: String) = TerminalFramePart(
        revision,
        head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 1, cursor = TerminalCursor(0, 0), palette = palette),
        lines = listOf(TerminalLine(0, listOf(TerminalRun(text = text)))),
    )

    /** About 2 KB of output on row 0, as `yes | head -100000` makes. */
    private fun delta(revision: Long) = TerminalFramePart(
        revision,
        head = TerminalFrameHead(TerminalFrameKind.DELTA, 80, 1, cursor = TerminalCursor(0, 0), history = 25, scroll = 26),
        lines = (-25..0).map { TerminalLine(it, listOf(TerminalRun(text = "y".repeat(79)))) },
    )

    @Test
    fun aFloodOfFramesIsBounded() {
        val queue = TerminalPushQueue()
        queue.offer(Frame("t-1", snapshot(1, "$")))
        for (r in 2L..20_001L) queue.offer(Frame("t-1", delta(r)))
        assertTrue(queue.queuedWeight <= TerminalPushQueue.MAX_QUEUED_WEIGHT, "${queue.queuedWeight}")
        assertTrue(queue.queuedPushes < 2_000, "${queue.queuedPushes}")
        assertTrue(queue.droppedFrames > 18_000, "${queue.droppedFrames}")
    }

    @Test
    fun framesDroppedInAFloodBecomeOneResync() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                queue.offer(Frame("t-1", snapshot(1, "$")))
                for (r in 2L..20_001L) queue.offer(Frame("t-1", delta(r)))
                val kept = queue.queuedPushes
                // The host answers the resync with a snapshot, after the flood.
                val assembler = TerminalFrameAssembler()
                val screen = TerminalScreen()
                var resyncs = 0
                val drained = queue.pushes.take(kept).toList()
                assertEquals(Opened("t-1"), drained.first())
                for (push in drained.drop(1)) {
                    val result = assembler.receive((push as Frame).part)
                    if (result.resync) resyncs++
                    result.frame?.let(screen::apply)
                }
                assertEquals(1, resyncs)
                assertTrue(assembler.awaitingSnapshot)
                queue.offer(Frame("t-1", snapshot(20_002, "fresh")))
                val result = assembler.receive((queue.pushes.take(1).toList().single() as Frame).part)
                assertEquals(false, result.resync)
                result.frame?.let(screen::apply)
                assertEquals(listOf("fresh"), screen.screenText())
                assertEquals(0, queue.queuedWeight)
            }
        }
    }

    @Test
    fun aLostPartIsAGapOfItsOwn() {
        val assembler = TerminalFrameAssembler()
        assertEquals(TerminalAssemblyResult(frame = snapshotFrame(), resync = false), assembler.receive(snapshot(1, "$")))
        assertEquals(TerminalAssemblyResult(resync = true), assembler.receive(TerminalFramePart.LOST))
        assertEquals(TerminalAssemblyResult(), assembler.receive(TerminalFramePart.LOST))
        assertEquals(1L, assembler.revision)
        assertEquals(TerminalAssemblyResult(), assembler.receive(delta(2)))
    }

    @Test
    fun opensAndEndsAreNeverDropped() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                for (r in 1L..20_000L) queue.offer(Frame("t-1", delta(r)))
                queue.offer(Ended("t-1", TerminalViewEndReason.GONE))
                queue.offer(Opened("t-2"))
                for (r in 1L..20_000L) queue.offer(Frame("t-2", delta(r)))
                val all = queue.pushes.take(queue.queuedPushes).toList()
                assertEquals(listOf(Ended("t-1", TerminalViewEndReason.GONE), Opened("t-2")), all.filter { it !is Frame })
                assertTrue(all.indexOf(Ended("t-1", TerminalViewEndReason.GONE)) < all.indexOf(Opened("t-2")))
                // Each terminal's dropped run ends in one lost part, after the frames kept before it.
                assertEquals(Frame("t-1", TerminalFramePart.LOST), all[all.indexOf(Ended("t-1", TerminalViewEndReason.GONE)) - 1])
                assertEquals(Frame("t-2", TerminalFramePart.LOST), all.last())
            }
        }
    }

    @Test
    fun closeCompletesThePushes() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                queue.close()
                queue.offer(Opened("t-2"))
                assertEquals(listOf<TerminalViewPush>(Opened("t-1")), queue.pushes.toList())
            }
        }
    }

    private fun snapshotFrame() = snapshot(1, "$").let { TerminalGridFrame(it.head!!, it.styles, it.lines) }
}
