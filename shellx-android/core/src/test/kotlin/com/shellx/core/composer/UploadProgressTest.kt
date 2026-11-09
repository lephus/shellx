package com.shellx.core.composer

import java.util.concurrent.Executors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class UploadProgressTest {
    @Test fun fractionIsZeroThenFollowsUpwardAndIsNilAfter() { runTest {
        val upload = UploadProgress(backgroundScope)
        val gate = CompletableDeferred<Unit>()
        val sending = async {
            upload.track { progress ->
                progress(0.5); progress(0.25); progress(2.0); gate.await(); "done"
            }
        }
        runCurrent()
        assertEquals(1.0, upload.fraction.value)
        gate.complete(Unit)
        assertEquals("done", sending.await())
        runCurrent()
        assertNull(upload.fraction.value)
    } }

    /**
     * Review Focus 4: 3B calls progress on Dispatchers.Default. It runs on a real single-thread "main" dispatcher,
     * because the point is a progress call from another thread: it is applied on the model's scope, only upward, and
     * never after its send ended. (Real threads: no virtual time here.)
     */
    @Test fun progressFromAnotherThreadNeverOutlivesItsSend() {
        val main = Executors.newSingleThreadExecutor { Thread(it, "main") }.asCoroutineDispatcher()
        try {
            runBlocking(main) {
                val upload = UploadProgress(CoroutineScope(SupervisorJob() + main))
                var late: ((Double) -> Unit)? = null
                val result = upload.track { progress ->
                    late = progress
                    withContext(Dispatchers.Default) { progress(0.5); progress(0.25) }
                    withTimeout(5.seconds) { while (upload.fraction.value != 0.5) delay(1) }
                    "done"
                }
                assertEquals("done", result)
                assertNull(upload.fraction.value)
                withContext(Dispatchers.Default) { late!!(0.9) }
                delay(50)
                assertNull(upload.fraction.value)
            }
        } finally {
            main.close()
        }
    }
}
