package com.shellx.app.screenshots

import android.animation.ValueAnimator
import androidx.compose.runtime.Composable
import com.github.takahirom.roborazzi.captureRoboImage
import com.shellx.app.ui.theme.ShellXTheme
import java.io.File
import javax.imageio.ImageIO
import org.robolectric.RuntimeEnvironment

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

    /**
     * Renders [content] inside [ShellXTheme] for light-en, dark-en, light-vi and dark-vi, in that order. Each is one
     * still frame: the system's animations are off while capturing (as with "Remove animations"), so a view that would
     * turn forever (the waiting border) draws its still frame, and Roborazzi's wait for an idle main looper ends.
     */
    fun capture(name: String, content: @Composable () -> Unit): List<Snapshot> = withoutAnimations { render(name, content) }

    private fun render(name: String, content: @Composable () -> Unit): List<Snapshot> {
        val dir = System.getProperty("shellx.snapshot.dir")
            ?: error("shellx.snapshot.dir is not set; run shellx-android/scripts/dev.sh test screenshots")
        val folder = File(dir).apply { mkdirs() }
        val shots = mutableListOf<Snapshot>()
        for (language in listOf("en", "vi")) {
            for (theme in listOf("light", "dark")) {
                RuntimeEnvironment.setQualifiers("+$language-${if (theme == "dark") "night" else "notnight"}")
                val file = File(folder, "$name-$theme-$language.png")
                captureRoboImage(file.absolutePath) { ShellXTheme { content() } }
                val image = ImageIO.read(file) ?: error("could not read $file")
                val width = image.width
                val height = image.height
                val argb = image.getRGB(0, 0, width, height, null, 0, width)
                shots += Snapshot(name, theme, language, file, width, height, argb)
            }
        }
        return shots
    }

    /** `ValueAnimator.setDurationScale` is hidden; Robolectric runs it (its shadow) for the test's sandbox only. */
    private fun <T> withoutAnimations(block: () -> T): T {
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
