package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.components.waitingBorder
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A frame of the waiting border is really drawn (WaitingBorderRenderTests.swift's card test): the frames are taken
 * while the gradient may be at any angle, so they only check what holds at every angle.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class WaitingBorderRenderTest {
    @Composable
    private fun card(active: Boolean) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            Box(
                Modifier.padding(16.dp).fillMaxWidth().height(64.dp).clip(RoundedCornerShape(14.dp))
                    .background(ShellXTheme.colors.surface).waitingBorder(active, 14.dp),
            )
        }
    }

    /** Pixel row y = 49 (inside the 6 px stroke that starts at y = 48), clear of the 42 px corners. */
    private fun topEdge(shot: Snapshot): List<Int> = (90 until shot.width - 90).map { shot.pixel(it, 49) }

    @Test
    fun aBorderedCardHasAColouredTopEdgeAndAPlainOneDoesNot() {
        val bordered = assertRenders("waiting-border-card") { card(active = true) }
        val plain = assertRenders("waiting-border-card-plain") { card(active = false) }
        assertEquals(bordered.size, plain.size)

        for ((withBorder, without) in bordered.zip(plain)) {
            val top = topEdge(withBorder)
            val coloured = top.count { chroma(it) > 80 }
            assertTrue(
                "${withBorder.file.name}: most of the top edge is coloured ($coloured of ${top.size})",
                coloured * 2 >= top.size,
            )
            val samples = top.filterIndexed { i, _ -> i % 5 == 0 }
            val widest = samples.maxOf { a -> samples.maxOf { b -> colourDistance(a, b) } }
            assertTrue("${withBorder.file.name}: several colours, not one ($widest)", widest > 100)

            val quiet = topEdge(without)
            assertEquals("${without.file.name}: a plain card has no colour", 0, quiet.count { chroma(it) > 40 })
        }
    }
}
