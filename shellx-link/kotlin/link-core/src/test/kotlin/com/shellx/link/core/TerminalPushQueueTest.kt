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
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
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
        queue.offer(Opened("t-1"))
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
                queue.offer(Opened("t-1"))
                for (r in 1L..20_000L) queue.offer(Frame("t-1", delta(r)))
                queue.offer(Ended("t-1", TerminalViewEndReason.GONE))
                queue.offer(Opened("t-2"))
                for (r in 1L..20_000L) queue.offer(Frame("t-2", delta(r)))
                val all = queue.pushes.take(queue.queuedPushes).toList()
                assertEquals(
                    listOf(Opened("t-1"), Ended("t-1", TerminalViewEndReason.GONE), Opened("t-2")),
                    all.filter { it !is Frame },
                )
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

    /** Fills [queue] with frames of t-2, a terminal not viewed, until the next would not fit the bound. */
    private fun fillWithAnotherTerminal(queue: TerminalPushQueue) {
        var r = 1L
        val dropped = queue.droppedFrames
        while (queue.droppedFrames == dropped) queue.offer(Frame("t-2", delta(r++)))
    }

    /**
     * Re-review A, m6: a snapshot of the view in three parts, arriving while the queue is full of another terminal's
     * frames, is kept whole, past the bound, and the assembler applies it.
     */
    @Test
    fun aViewedSnapshotOfThreePartsOverTheBoundIsKeptWhole() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                fillWithAnotherTerminal(queue)
                val dropped = queue.droppedFrames
                val head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 300, 120, cursor = TerminalCursor(0, 0), palette = palette)
                val parts = (0 until 3).map { p ->
                    TerminalFramePart(
                        1, part = p, parts = 3, head = if (p == 0) head else null,
                        lines = (p * 40 until p * 40 + 40).map { TerminalLine(it, listOf(TerminalRun(text = "x".repeat(300)))) },
                    )
                }
                parts.forEach { queue.offer(Frame("t-1", it)) }
                assertEquals(dropped, queue.droppedFrames)
                assertTrue(queue.queuedWeight > TerminalPushQueue.MAX_QUEUED_WEIGHT, "${queue.queuedWeight}")
                val view = List(queue.queuedPushes) { queue.pushes.first() }.filter { it.terminalId == "t-1" }
                assertEquals(listOf<TerminalViewPush>(Opened("t-1")) + parts.map { Frame("t-1", it) }, view)
                val assembler = TerminalFrameAssembler()
                val screen = TerminalScreen()
                for (push in view.drop(1)) assembler.receive((push as Frame).part).frame?.let(screen::apply)
                assertEquals(List(120) { "x".repeat(300) }, screen.screenText())
            }
        }
    }

    /**
     * Re-review A, m6: the I-1 freeze avoided by the exemption itself. The answer to the resync arrives while the queue
     * is full of another terminal's frames (not the view's, which the rule after a LOST would have dropped), and it is
     * still kept.
     */
    @Test
    fun aResyncAnswerIsKeptOverAQueueFullOfAnotherTerminal() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                val assembler = TerminalFrameAssembler()
                val screen = TerminalScreen()
                var resyncs = 0
                fun feed(push: TerminalViewPush) {
                    if (push !is Frame || push.terminalId != "t-1") return
                    val result = assembler.receive(push.part)
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
                fillWithAnotherTerminal(queue)
                val answer = r++
                queue.offer(Frame("t-1", snapshot(answer, "fresh")))
                List(queue.queuedPushes) { queue.pushes.first() }.forEach(::feed)
                assertEquals(1, resyncs)
                assertFalse(assembler.awaitingSnapshot)
                assertEquals(answer, assembler.revision)
                assertEquals(listOf("fresh"), screen.screenText())
            }
        }
    }

    /** The weight [TerminalPushQueue] gives [part], read off an empty queue. */
    private fun weightOf(part: TerminalFramePart) = TerminalPushQueue().apply { offer(Frame("t-9", part)) }.queuedWeight

    /**
     * Re-review A, I-1: only the parts a snapshot still lacks, in order, skip the bound. A part sent again, out of
     * order or after the snapshot is complete follows the bound like a delta, so the bound holds whatever the host
     * sends.
     */
    @Test
    fun aSnapshotPartRepeatedPastItsCountStaysBounded() {
        val queue = TerminalPushQueue()
        queue.offer(Opened("t-1"))
        val head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 1, cursor = TerminalCursor(0, 0), palette = palette)
        val part0 = TerminalFramePart(2, part = 0, parts = 2, head = head)
        val part1 = TerminalFramePart(2, part = 1, parts = 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "x".repeat(60_000))))))
        queue.offer(Frame("t-1", part0))
        repeat(100) { queue.offer(Frame("t-1", part1)) }
        val bound = TerminalPushQueue.MAX_QUEUED_WEIGHT + weightOf(part0) + weightOf(part1)
        assertTrue(queue.queuedWeight <= bound, "${queue.queuedWeight} > $bound")
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

    /**
     * Re-review A, m4: frames of a terminal other than the one viewed follow the bound and leave nothing behind, so a
     * host that names many terminals grows neither the queue's markers nor its state. The viewed terminal's state goes
     * with its Ended.
     */
    @Test
    fun onlyTheTerminalViewedLeavesStateBehind() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                val wide = TerminalFramePart(1, part = 0, parts = 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "x".repeat(60_000))))))
                repeat(1_000) { queue.offer(Frame("x-$it", wide)) }
                assertTrue(queue.queuedWeight <= TerminalPushQueue.MAX_QUEUED_WEIGHT)
                val others = List(queue.queuedPushes) { queue.pushes.first() }
                assertEquals(0, others.count { it is Frame && it.part == TerminalFramePart.LOST }, "LOST parts of terminals not viewed")
                assertTrue(others.size < 40, "${others.size}")

                queue.offer(Frame("t-1", snapshot(1, "$")))
                var r = 2L
                val dropped = queue.droppedFrames
                while (queue.droppedFrames == dropped) queue.offer(Frame("t-1", delta(r++)))
                queue.offer(Ended("t-1", TerminalViewEndReason.GONE))
                List(queue.queuedPushes) { queue.pushes.first() }
                // t-1 is no longer viewed and waits for no snapshot: its next frame is kept.
                queue.offer(Frame("t-1", delta(r)))
                assertEquals(listOf<TerminalViewPush>(Frame("t-1", delta(r))), List(queue.queuedPushes) { queue.pushes.first() })
            }
        }
    }

    /**
     * Re-review A, m2: two collectors wait; the offer's wake-up goes to the first, which is cancelled before it runs. The
     * second still gets the push, with no other offer.
     */
    @Test
    fun aTokenTakenByACancelledCollectorStillWakesTheNext() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                val first = launch(start = CoroutineStart.UNDISPATCHED) { queue.pushes.first() }
                val second = async(start = CoroutineStart.UNDISPATCHED) { queue.pushes.first() }
                queue.offer(Frame("t-1", snapshot(1, "$")))
                first.cancel()
                assertEquals(Frame("t-1", snapshot(1, "$")), second.await())
            }
        }
    }

    /**
     * Re-review A, m2: a push the queue takes for a collector reaches that collector's code, even when the collector
     * was cancelled since its last push (as from another thread). A LOST part lost there would freeze the view.
     */
    @Test
    fun aCollectorCancelledBetweenTwoPushesLosesNeither() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                queue.offer(Frame("t-1", TerminalFramePart.LOST))
                val seen = mutableListOf<TerminalViewPush>()
                launch {
                    queue.pushes.collect {
                        seen += it
                        if (it is Opened) currentCoroutineContext().cancel()
                    }
                }.join()
                val left = List(queue.queuedPushes) { queue.pushes.first() }
                assertEquals(listOf(Opened("t-1"), Frame("t-1", TerminalFramePart.LOST)), seen + left)
            }
        }
    }

    /**
     * Re-review A2, minor 1: a collector cancelled while it emits takes nothing more. What it has not taken stays
     * queued for the next collector, a LOST part included.
     */
    @Test
    fun aCancelledCollectorLeavesWhatItHasNotTaken() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                queue.offer(Frame("t-1", delta(2)))
                queue.offer(Frame("t-1", TerminalFramePart.LOST))
                val seen = mutableListOf<TerminalViewPush>()
                launch {
                    queue.pushes.collect {
                        seen += it
                        if (it is Opened) currentCoroutineContext().cancel()
                    }
                }.join()
                assertEquals(listOf<TerminalViewPush>(Opened("t-1")), seen)
                assertEquals(2, queue.queuedPushes)
            }
        }
    }

    /**
     * Re-review B, out of scope 1: Opened and Ended weigh nothing, so while nobody collects, a host that streams
     * `terminal.view.ended` for terminals the session does not view must not grow the queue without bound. The viewed
     * terminal's Ended is never dropped, and each Ended of a terminal not viewed passes while few are queued (the host
     * answers every input, resize or resync of a terminal not open with one, PROTOCOL.md 11.1).
     */
    @Test
    fun endedOfTerminalsNotViewedStayBoundedWithNoCollector() {
        runBlocking {
            within {
                val queue = TerminalPushQueue()
                queue.offer(Opened("t-1"))
                repeat(100_000) { queue.offer(Ended("x-$it", TerminalViewEndReason.GONE)) }
                repeat(100_000) { queue.offer(Ended("t-2", TerminalViewEndReason.NOT_OPEN)) }
                assertTrue(queue.queuedPushes < 100, "${queue.queuedPushes}")

                queue.offer(Ended("t-1", TerminalViewEndReason.GONE))
                val all = List(queue.queuedPushes) { queue.pushes.first() }
                assertEquals(Opened("t-1"), all.first())
                assertEquals(Ended("t-1", TerminalViewEndReason.GONE), all.last())

                queue.offer(Ended("t-2", TerminalViewEndReason.NOT_OPEN))
                queue.offer(Ended("t-2", TerminalViewEndReason.NOT_OPEN))
                assertEquals(
                    List<TerminalViewPush>(2) { Ended("t-2", TerminalViewEndReason.NOT_OPEN) },
                    List(queue.queuedPushes) { queue.pushes.first() },
                )
            }
        }
    }

    private fun snapshotFrame() = snapshot(1, "$").let { TerminalGridFrame(it.head!!, it.styles, it.lines) }
}
