package com.shellx.core.update

import com.shellx.core.testing.Gate
import com.shellx.core.testing.eventually
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest

/** Offering a newer Play version (S3 §7.3: a flexible in-app update). The app checks at launch and on every return;
 *  Later hides the prompt until the next check. */
class UpdatePromptTest {
    /** A store that answers from a queue (an empty queue answers "no update") and can hold its answers. */
    private class FakeChecker(answers: List<Result<AvailableUpdate?>>, holding: Boolean = false) : UpdateChecker {
        private val queue = ArrayDeque(answers)
        private val gate: Gate? = if (holding) Gate() else null

        var asked = 0
            private set
        val started = mutableListOf<AvailableUpdate>()

        override suspend fun check(): AvailableUpdate? {
            asked += 1
            gate?.wait()
            return (queue.removeFirstOrNull() ?: Result.success(null)).getOrThrow()
        }

        override suspend fun startUpdate(update: AvailableUpdate) {
            started += update
        }

        fun release() {
            gate?.open()
        }
    }

    private fun answer(versionCode: Long): Result<AvailableUpdate?> = Result.success(AvailableUpdate(versionCode))

    @Test fun aNewerVersionIsOffered() { runTest {
        val prompt = UpdatePrompt(100, FakeChecker(listOf(answer(101))))

        prompt.check()

        assertEquals(AvailableUpdate(101), prompt.offered.value)
    } }

    @Test fun theInstalledOrAnOlderVersionIsNotOffered() { runTest {
        for (versionCode in listOf(100L, 99L)) {
            val prompt = UpdatePrompt(100, FakeChecker(listOf(answer(versionCode))))
            prompt.check()
            assertNull(prompt.offered.value, "$versionCode")
        }
    } }

    @Test fun laterHidesItUntilTheNextCheck() { runTest {
        val prompt = UpdatePrompt(100, FakeChecker(listOf(answer(101), answer(101))))
        prompt.check()

        prompt.later()
        assertNull(prompt.offered.value)

        prompt.check()
        assertEquals(101L, prompt.offered.value?.versionCode, "the next time the app opens it asks again")
    } }

    @Test fun aFailedLookupShowsNothing() { runTest {
        val prompt = UpdatePrompt(100, FakeChecker(listOf(Result.failure(IOException("offline")))))

        prompt.check()

        assertNull(prompt.offered.value)
    } }

    @Test fun aStoreThatNoLongerHasTheNewerVersionTakesTheOfferBack() { runTest {
        val prompt = UpdatePrompt(100, FakeChecker(listOf(answer(101), answer(100))))

        prompt.check()
        prompt.check()

        assertNull(prompt.offered.value)
    } }

    @Test fun asksTheStoreOnceWhileALookupIsUnderWay() { runTest {
        val checker = FakeChecker(listOf(answer(101)), holding = true)
        val prompt = UpdatePrompt(100, checker)

        // Launch and coming to the front both check, at about the same time.
        val first = backgroundScope.async { prompt.check() }
        val second = backgroundScope.async { prompt.check() }
        assertTrue(eventually { checker.asked > 0 })
        checker.release()
        first.await()
        second.await()

        assertEquals(1, checker.asked)
        assertEquals(101L, prompt.offered.value?.versionCode)
    } }

    @Test fun updateStartsTheStoresFlowAndHidesThePrompt() { runTest {
        val checker = FakeChecker(listOf(answer(101)))
        val prompt = UpdatePrompt(100, checker)
        prompt.check()

        prompt.update()

        assertEquals(listOf(AvailableUpdate(101)), checker.started)
        assertNull(prompt.offered.value)
        // Nothing offered: nothing to start.
        prompt.update()
        assertEquals(1, checker.started.size)
    } }
}
