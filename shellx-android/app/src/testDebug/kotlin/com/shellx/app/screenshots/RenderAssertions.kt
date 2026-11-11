package com.shellx.app.screenshots

import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.shellx.app.ui.components.LocalSpinner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

/**
 * [ShellXSnapshots.capture] with the iPhone render tests' checks: light-en, dark-en, light-vi, dark-vi, each a file
 * 1179 px wide (393 dp at xxhdpi; [width] for a test with other qualifiers), and light differs from dark in each
 * language. Every [com.shellx.app.ui.components.Spinner] in [content] is a still one, at 70 % (an endless animation
 * never settles). [ready]: as in [ShellXSnapshots.capture].
 */
fun assertRenders(
    name: String,
    ready: (() -> Boolean)? = null,
    width: Int = 1179,
    content: @Composable () -> Unit,
): List<Snapshot> {
    val shots = ShellXSnapshots.capture(name, ready = ready) {
        CompositionLocalProvider(LocalSpinner provides StillSpinner, content = content)
    }
    assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
    for (shot in shots) {
        assertTrue("${shot.file} was written", shot.file.isFile)
        assertEquals("$name-${shot.theme}-${shot.language}.png", shot.file.name)
        assertEquals("${shot.file.name} is $width px wide (393 dp at xxhdpi is 1179)", width, shot.width)
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

/** A determinate spinner at 70 %: what a wait looks like in a render. */
val StillSpinner: @Composable (androidx.compose.ui.Modifier, androidx.compose.ui.unit.Dp) -> Unit = { modifier, strokeWidth ->
    CircularProgressIndicator(progress = { 0.7f }, modifier = modifier, strokeWidth = strokeWidth)
}
