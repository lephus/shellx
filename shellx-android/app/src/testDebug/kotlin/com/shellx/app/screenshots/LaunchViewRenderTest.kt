package com.shellx.app.screenshots

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.LaunchView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class LaunchViewRenderTest {
    @Test
    fun rendersInLightAndDarkInEnglishAndVietnamese() {
        val shots = ShellXSnapshots.capture("launch") { LaunchView() }

        assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
        val metrics = RuntimeEnvironment.getApplication().resources.displayMetrics
        for (shot in shots) {
            assertTrue(shot.file.isFile)
            assertEquals("launch-${shot.theme}-${shot.language}.png", shot.file.name)
            assertEquals(1179, shot.width) // 393 dp at xxhdpi: the iPhone 16's 1179 px
            assertEquals(metrics.heightPixels, shot.height)
        }
        val light = shots.first { it.theme == "light" && it.language == "en" }
        val dark = shots.first { it.theme == "dark" && it.language == "en" }
        assertEquals(0xFFF2F2F7.toInt(), light.pixel(10, 10))
        assertEquals(0xFF0B0716.toInt(), dark.pixel(10, 10))
        assertFalse(light.argb.contentEquals(dark.argb))
    }
}
