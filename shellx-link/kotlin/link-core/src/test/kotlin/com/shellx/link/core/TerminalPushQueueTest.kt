package com.shellx.link.core

import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Frame
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
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

    /**
     * Review A, I-1: during a flood the consumer reaches the gap and asks for a resync while output goes on; the
     * snapshot that answers it must still reach the assembler, or the view would freeze on its last screen.
     */
    @Test
    fun aSnapshotThatAnswersAResyncDuringAFloodStillArrives() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                val assembler = TerminalFrameAssembler()
                val screen = TerminalScreen()
                var resyncs = 0
                fun feed(push: TerminalViewPush) {
                    val result = assembler.receive((push as Frame).part)
                    if (result.resync) resyncs++
                    result.frame?.let(screen::apply)
                }
                queue.offer(Opened("t-1"))
                queue.offer(Frame("t-1", snapshot(1, "$")))
                var r = 2L
                while (queue.droppedFrames == 0L) queue.offer(Frame("t-1", delta(r++)))
                assertEquals(Opened("t-1"), queue.pushes.first())
                while (true) {
                    val push = queue.pushes.first()
                    feed(push)
                    if ((push as Frame).part == TerminalFramePart.LOST) break
                }
                assertEquals(1, resyncs)
                repeat(2_000) { queue.offer(Frame("t-1", delta(r++))) }
                val answer = r++
                queue.offer(Frame("t-1", snapshot(answer, "fresh")))
                repeat(10) { queue.offer(Frame("t-1", delta(r++))) }
                queue.pushes.take(queue.queuedPushes).toList().forEach(::feed)
                assertEquals(1, resyncs)
                assertFalse(assembler.awaitingSnapshot)
                assertEquals(answer + 10, assembler.revision)
                assertEquals(0, queue.queuedWeight)
            }
        }
    }

    /**
     * Review A, I-1: a snapshot of the terminal viewed is never dropped, even over the bound, and it replaces the frames
     * of that terminal it makes stale, so snapshots stay bounded at one per terminal however many the host sends.
     */
    @Test
    fun aSnapshotIsNeverDroppedAndReplacesWhatItMakesStale() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                var r = 1L
                while (queue.queuedWeight + 10_000 < TerminalPushQueue.MAX_QUEUED_WEIGHT) queue.offer(Frame("t-1", delta(r++)))
                val big = TerminalFramePart(
                    r++,
                    head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 300, 120, cursor = TerminalCursor(0, 0), palette = palette),
                    lines = (0 until 120).map { TerminalLine(it, listOf(TerminalRun(text = "x".repeat(300)))) },
                )
                queue.offer(Frame("t-1", big))
                assertEquals(0L, queue.droppedFrames)
                assertEquals(2, queue.queuedPushes)
                repeat(1_000) { queue.offer(Frame("t-1", big.copy(revision = r++))) }
                assertEquals(2, queue.queuedPushes)
                assertTrue(queue.queuedWeight < TerminalPushQueue.MAX_QUEUED_WEIGHT, "${queue.queuedWeight}")
                assertEquals(listOf(Opened("t-1"), Frame("t-1", big.copy(revision = r - 1))), queue.pushes.take(2).toList())
            }
        }
    }

    /** Review A, m5: no frame from the wire can equal LOST, because the codec refuses its fields both ways. */
    @Test
    fun lostIsNoFrameTheCodecTakes() {
        val lost = TerminalFramePart.LOST
        val encoded = assertFailsWith<LinkCodecException> { LinkCodec.encode(LinkMessage.TerminalViewFrame("t-1", lost)) }
        assertEquals(LinkCodecException.BadJson(null), encoded)
        val json = """{"v":1,"t":"terminal.view.frame","terminal_id":"t-1","revision":${lost.revision},"part":${lost.part},"parts":${lost.parts}}"""
        val decoded = assertFailsWith<LinkCodecException> { LinkCodec.decode(json.encodeToByteArray()) }
        assertEquals(LinkCodecException.BadJson(null), decoded)
    }

    /** Review A, m6: a frame weighs the UTF-8 bytes of its texts, as its JSON does, not their UTF-16 chars. */
    @Test
    fun weightCountsTheUtf8BytesOfTheText() {
        fun weightOf(text: String) = TerminalPushQueue().apply {
            offer(Frame("t-1", TerminalFramePart(1, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = text)))))))
        }.queuedWeight
        val ascii = weightOf("e".repeat(1_000))
        assertEquals(1_000, weightOf("é".repeat(1_000)) - ascii)
        assertEquals(2_000, weightOf("中".repeat(1_000)) - ascii)
        assertEquals(1_000, weightOf("😀".repeat(500)) - ascii)
    }

    /** Review A, I-2: the next collector gets the frame, and its weight is never lost (Task 6 cancels at every STOP). */
    @Test
    fun aCancelledCollectorGivesItsFrameBack() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                val waiting = launch(start = CoroutineStart.UNDISPATCHED) { queue.pushes.first() }
                queue.offer(Frame("t-1", snapshot(1, "$")))
                waiting.cancel()
                waiting.join()
                assertEquals(Frame("t-1", snapshot(1, "$")), queue.pushes.first())
                assertEquals(0, queue.queuedWeight)
                assertEquals(0, queue.queuedPushes)
            }
        }
    }

    private fun snapshotFrame() = snapshot(1, "$").let { TerminalGridFrame(it.head!!, it.styles, it.lines) }
}
