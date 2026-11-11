package com.shellx.app.screenshots

import android.animation.ValueAnimator
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.Composable
import com.github.takahirom.roborazzi.RoborazziComposeCaptureOption
import com.github.takahirom.roborazzi.RoborazziComposeOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.shellx.app.ui.theme.ShellXTheme
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.imageio.ImageIO
import kotlin.concurrent.thread
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowLooper

/** One rendered PNG: `<name>-<theme>-<language>.png`, with its pixels as ARGB. */
class Snapshot(
    val name: String,
    val theme: String,
    val language: String,
    val file: File,
    val width: Int,
    val height: Int,
    val argb: IntArray,
) {
    fun pixel(x: Int, y: Int): Int = argb[y * width + x]
}

/**
 * Render test support, like the iPhone's `SnapshotWriter`: renders a screen in light and dark, in English and
 * Vietnamese, and writes the PNGs into the folder named by the system property `shellx.snapshot.dir`
 * (`dev.sh test screenshots`, or `dev.sh screenshots record <dir>`). No golden images are compared.
 *
 * A render test is a `…RenderTest` class in this package with `@GraphicsMode(GraphicsMode.Mode.NATIVE)` and
 * `@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)`.
 */
object ShellXSnapshots {
    /** An iPhone 16's screen, 393 × 852 dp at 3x, the size the iPhone render tests draw at. */
    const val DEVICE_QUALIFIERS = "w393dp-h852dp-xxhdpi"

    /** How long one frame may take to settle; the first render with native graphics takes a few seconds. */
    val SETTLE_TIMEOUT: Duration = 60.seconds

    /**
     * Renders [content] inside [ShellXTheme] for light-en, dark-en, light-vi and dark-vi, in that order.
     *
     * The system's animators are off while capturing (as with "Remove animations"), so a view that reads
     * `ValueAnimator.areAnimatorsEnabled()` (the waiting border) draws its still frame. Compose's own infinite
     * transitions do not read it: an indeterminate `CircularProgressIndicator` (`GoogleSignInButton(busy = true)`
     * among them) keeps asking for frames, and Roborazzi's wait for an idle main looper never ends. Such a frame fails
     * after [settleTimeout] with its file name; render a determinate or still stand-in instead.
     *
     * [ready], when given, holds each capture until it is true, letting the main looper's time pass (up to
     * [READY_TIMEOUT_MS]): a screen fed by a live rig (a terminal's first screen) is drawn once it came, as the iPhone's
     * render tests settle first.
     */
    fun capture(
        name: String,
        settleTimeout: Duration = SETTLE_TIMEOUT,
        ready: (() -> Boolean)? = null,
        content: @Composable () -> Unit,
    ): List<Snapshot> = withoutAnimations { render(name, settleTimeout, ready, content) }

    /** The longest [capture] waits for its `ready`, in real time (a rig's stores work off the main thread). */
    const val READY_TIMEOUT_MS = 10_000L

    /** Holds a capture until [ready], the main looper's clock moving on 10 ms a round. */
    private class WaitUntilReady(private val what: String, private val ready: () -> Boolean) : RoborazziComposeCaptureOption {
        override fun beforeCapture() {
            val deadline = System.nanoTime() + READY_TIMEOUT_MS * 1_000_000
            while (System.nanoTime() < deadline) {
                if (ready()) return
                ShadowLooper.idleMainLooper(10, TimeUnit.MILLISECONDS)
                Thread.sleep(2)
            }
            if (!ready()) throw AssertionError("$what was not ready to capture within $READY_TIMEOUT_MS ms")
        }

        override fun afterCapture() = Unit
    }

    private fun render(name: String, settleTimeout: Duration, ready: (() -> Boolean)?, content: @Composable () -> Unit): List<Snapshot> {
        val dir = System.getProperty("shellx.snapshot.dir")
            ?: error("shellx.snapshot.dir is not set; run shellx-android/scripts/dev.sh test screenshots")
        val folder = File(dir).apply { mkdirs() }
        val shots = mutableListOf<Snapshot>()
        for (language in listOf("en", "vi")) {
            for (theme in listOf("light", "dark")) {
                RuntimeEnvironment.setQualifiers("+$language-${if (theme == "dark") "night" else "notnight"}")
                val file = File(folder, "$name-$theme-$language.png")
                val options = RoborazziComposeOptions { if (ready != null) addOption(WaitUntilReady(file.name, ready)) }
                settlingWithin(settleTimeout, file.name) {
                    captureRoboImage(file.absolutePath, roborazziComposeOptions = options) { ShellXTheme { content() } }
                }
                val image = ImageIO.read(file) ?: error("could not read $file")
                val width = image.width
                val height = image.height
                val argb = image.getRGB(0, 0, width, height, null, 0, width)
                shots += Snapshot(name, theme, language, file, width, height, argb)
            }
        }
        return shots
    }

    /**
     * Runs [block] (one capture, on the main looper's thread) with a watchdog: once [timeout] passes before it returns,
     * the watchdog posts a failure to the main looper, which the busy looper runs in turn, so the capture throws
     * instead of hanging the run. Roborazzi's clean-up waits on the same looper, so the watchdog posts again every
     * second until [block] returns.
     */
    private fun <T> settlingWithin(timeout: Duration, what: String, block: () -> T): T {
        val main = Handler(Looper.getMainLooper())
        val settled = AtomicBoolean(false)
        val failure = Runnable {
            if (!settled.get()) {
                throw AssertionError(
                    "$what did not settle within $timeout: something on screen animates forever (an indeterminate " +
                        "CircularProgressIndicator?); render a determinate or still stand-in",
                )
            }
        }
        val watchdog = thread(isDaemon = true, name = "shellx-snapshot-watchdog") {
            try {
                var wait = timeout.inWholeMilliseconds
                while (!settled.get()) {
                    Thread.sleep(wait)
                    if (!settled.get()) main.post(failure)
                    wait = 1_000
                }
            } catch (_: InterruptedException) {
                // The capture returned.
            }
        }
        try {
            return block()
        } finally {
            settled.set(true)
            watchdog.interrupt()
            main.removeCallbacks(failure)
        }
    }

    /**
     * Runs [block] with the system's animations off, as with "Remove animations" (a screen read in it draws its still
     * frame). `ValueAnimator.setDurationScale` is hidden; Robolectric runs it (its shadow) for the test's sandbox only.
     */
    fun <T> withoutAnimations(block: () -> T): T {
        val setScale = ValueAnimator::class.java.getMethod("setDurationScale", Float::class.javaPrimitiveType)
        val before = ValueAnimator.getDurationScale()
        setScale.invoke(null, 0f)
        try {
            return block()
        } finally {
            setScale.invoke(null, before)
        }
    }
}
