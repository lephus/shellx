package com.shellx.app.screenshots

import androidx.compose.material3.CircularProgressIndicator
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The capture helper itself (review B m-4): a view that animates forever through Compose's own clock, which the
 * animator switch does not reach, fails the capture with its cause instead of hanging the run.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class ShellXSnapshotsTest {
    @Test
    fun aRenderThatNeverSettlesFailsWithItsCause() {
        val started = System.nanoTime()
        val error = assertThrows(AssertionError::class.java) {
            ShellXSnapshots.capture("never-settles", settleTimeout = 5.seconds) { CircularProgressIndicator() }
        }
        val message = error.message.orEmpty()
        assertTrue(message, "never-settles-light-en" in message && "did not settle" in message)
        val seconds = (System.nanoTime() - started) / 1_000_000_000
        assertTrue("failed after $seconds s", seconds < 60)
    }
}
