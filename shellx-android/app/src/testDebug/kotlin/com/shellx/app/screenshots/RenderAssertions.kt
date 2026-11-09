package com.shellx.app.screenshots

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

/**
 * [ShellXSnapshots.capture] with the iPhone render tests' checks: light-en, dark-en, light-vi, dark-vi, each a file
 * 1179 px wide (393 dp at xxhdpi), and light differs from dark in each language.
 */
fun assertRenders(name: String, content: @Composable () -> Unit): List<Snapshot> {
    val shots = ShellXSnapshots.capture(name, content)
    assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
    for (shot in shots) {
        assertTrue("${shot.file} was written", shot.file.isFile)
        assertEquals("$name-${shot.theme}-${shot.language}.png", shot.file.name)
        assertEquals("${shot.file.name} is 393 dp wide at xxhdpi", 1179, shot.width)
    }
    for (language in listOf("en", "vi")) {
        val light = shots.first { it.theme == "light" && it.language == language }
        val dark = shots.first { it.theme == "dark" && it.language == language }
        assertFalse("$name-$language: light and dark renders should differ", light.argb.contentEquals(dark.argb))
    }
    return shots
}

/** Text at font scale 2 (the iPhone tests' accessibility3), through [LocalDensity]. */
@Composable
fun LargeText(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f), content = content)
}
