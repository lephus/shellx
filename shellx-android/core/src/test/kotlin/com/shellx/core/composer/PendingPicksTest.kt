package com.shellx.core.composer

import com.shellx.core.testing.Gate
import com.shellx.core.testing.eventually
import com.shellx.link.core.AttachmentKind
import java.io.IOException
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * Photos and files still being read for the composer: each holds a place until it is read, in the order picked, and
 * each can be cancelled, which frees its place at once even when its read never ends.
 */
class PendingPicksTest {
    private fun attachment(name: String) =
        OutgoingAttachment(kind = AttachmentKind.FILE, name = name, data = name.encodeToByteArray())

    @Test fun picksArriveInTheOrderPicked() { runTest {
        val picks = PendingPicks(backgroundScope)
        val added = mutableListOf<String>()
        picks.read(
            listOf<suspend () -> OutgoingAttachment>(
                { attachment("a.txt") },
                {
                    delay(20.milliseconds)
                    attachment("b.txt")
                },
                { attachment("c.txt") },
            ),
        ) { result -> result.onSuccess { added += it.name } }
        assertEquals(3, picks.count, "each pick holds a place from the moment the picker closes")

        assertTrue(eventually { picks.count == 0 })
        assertEquals(listOf("a.txt", "b.txt", "c.txt"), added)
    } }

    @Test fun aPickThatCannotBeReadSaysWhy() { runTest {
        val picks = PendingPicks(backgroundScope)
        var failures = 0
        picks.read(listOf<suspend () -> OutgoingAttachment>({ throw IOException("unreadable") })) { result ->
            if (result.isFailure) failures += 1
        }
        assertTrue(eventually { picks.count == 0 })
        assertEquals(1, failures)
    } }

    /** The way out of a read that never ends: its ✕ frees the composer at once, the next pick goes on, and what the
     *  hung read returns later is dropped. */
    @Test fun aHungPickIsCancelledAtOnce() { runTest {
        val picks = PendingPicks(backgroundScope)
        // A read the test ends by hand; it ignores cancellation, like a file read that hangs.
        val hung = Gate()
        val added = mutableListOf<String>()
        val ids = picks.read(
            listOf<suspend () -> OutgoingAttachment>(
                {
                    hung.wait()
                    attachment("late.txt")
                },
                { attachment("next.txt") },
            ),
        ) { result -> result.onSuccess { added += it.name } }
        assertTrue(eventually { hung.waiting == 1 })
        assertEquals(ids, picks.ids.value)

        picks.cancel(ids[0])
        assertEquals(listOf(ids[1]), picks.ids.value, "the cancelled pick's place is gone before its read ends")

        assertTrue(eventually { picks.count == 0 }, "the pick after the hung one was read")
        assertEquals(listOf("next.txt"), added)

        hung.open()
        delay(50.milliseconds)
        runCurrent()
        assertEquals(listOf("next.txt"), added, "a cancelled pick's late result is dropped")
    } }

    @Test fun aPickCancelledBeforeItsTurnIsNeverRead() { runTest {
        val picks = PendingPicks(backgroundScope)
        val first = Gate()
        val calls = mutableListOf<String>()
        val added = mutableListOf<String>()
        val ids = picks.read(
            listOf<suspend () -> OutgoingAttachment>(
                {
                    calls += "first"
                    first.wait()
                    attachment("first.txt")
                },
                {
                    calls += "second"
                    attachment("second.txt")
                },
                {
                    calls += "third"
                    attachment("third.txt")
                },
            ),
        ) { result -> result.onSuccess { added += it.name } }
        assertTrue(eventually { first.waiting == 1 })

        picks.cancel(ids[1])
        assertEquals(2, picks.count)
        first.open()

        assertTrue(eventually { picks.count == 0 })
        assertEquals(listOf("first", "third"), calls)
        assertEquals(listOf("first.txt", "third.txt"), added)
    } }

    /** Cancelling a pick cancels its read, so a read that does watch for it (a photo load) stops. */
    @Test fun cancellingAPickCancelsItsRead() { runTest {
        val picks = PendingPicks(backgroundScope)
        var sawCancellation = false
        var entered = false
        var reported = 0
        val ids = picks.read(
            listOf<suspend () -> OutgoingAttachment>(
                {
                    entered = true
                    try {
                        delay(30.seconds)
                    } catch (e: CancellationException) {
                        sawCancellation = true
                        throw e
                    }
                    attachment("never.txt")
                },
            ),
        ) { reported += 1 }
        assertTrue(eventually { entered })

        picks.cancel(ids[0])
        assertEquals(0, picks.count)
        assertTrue(eventually { sawCancellation })
        assertEquals(0, reported, "a cancelled pick reports nothing")
    } }

    @Test fun cancellingAnUnknownPickDoesNothing() { runTest {
        val picks = PendingPicks(backgroundScope)
        picks.cancel(UUID.randomUUID().toString())
        assertEquals(0, picks.count)
    } }
}
