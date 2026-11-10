package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.content.Context
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.terminal.TerminalFont
import com.shellx.app.ui.terminal.TerminalPane
import com.shellx.core.demo.DemoTerminalFixture
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.core.terminal.TerminalGeometry
import com.shellx.core.terminal.TerminalUnavailableReason
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.terminal.TerminalViewPhase
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalScreen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A shell chip's page (`TerminalRenderTests.swift`): the Mac's terminal drawn from fixed screens (a shell, vim, htop, a
 * 320-column Mac window, wide characters, an agent) and the pages shown while it cannot be drawn.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class TerminalRenderTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** `fixture.snapshot`, then each delta, applied to a fresh screen. */
    private fun screen(fixture: DemoTerminalFixture, deltas: List<TerminalGridFrame> = emptyList()): TerminalScreen =
        TerminalScreen().apply {
            apply(fixture.snapshot)
            for (delta in deltas) apply(delta)
        }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun page(model: TerminalViewModel) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            TopAppBar(title = { Text("shellx-ios") })
            TerminalPane(model, model.terminalId ?: "t", "zsh", shown = true, modifier = Modifier.weight(1f))
        }
    }

    /** The scale that fits [cols] columns into the device's width at the terminal's font. */
    private fun fitAtDeviceWidth(cols: Int): Float {
        val metrics = context.resources.displayMetrics
        return TerminalGeometry.fitScale(
            cols, TerminalFont(context).cellWidth, metrics.widthPixels.toFloat(), TerminalGeometry.PADDING_DP * metrics.density,
        )
    }

    @Test
    fun rendersANormalShell() {
        val screen = screen(DemoTerminalScreens.SHELL, listOf(DemoTerminalScreens.SHELL_TYPING))
        assertEquals(29, screen.cursor?.x)
        assertRenders("terminal-shell") { page(TerminalViewModel.fixed("t-zsh", screen)) }
    }

    @Test
    fun rendersVimOnTheAlternateScreen() {
        val screen = screen(DemoTerminalScreens.VIM)
        assertTrue(screen.alt)
        assertEquals(0, screen.historyRows.size)
        assertRenders("terminal-vim") { page(TerminalViewModel.fixed("t-vim", screen)) }
    }

    @Test
    fun rendersHtopFittedToWidth() { // Review Focus 5
        val fit = fitAtDeviceWidth(100)
        assertTrue("fit $fit", fit < 1f)
        assertTrue("fit $fit", fit > 0.3f)
        assertRenders("terminal-htop") { page(TerminalViewModel.fixed("t-htop", screen(DemoTerminalScreens.HTOP))) }
    }

    @Test
    fun rendersA320ColumnGridFittedToWidth() { // Review Focus 5, contracts §17
        val ruler = "0123456789".repeat(31) + "012345" // 316 columns
        val wideMac = DemoTerminalFixture(
            cols = 320, rows = 130,
            screen = (0 until 130).map { DemoTerminalScreens.runs("{5}" + "%03d".format(it) + "{0} " + ruler) },
            cursor = TerminalCursor(0, 129),
        )
        val screen = screen(wideMac)
        assertEquals(320, screen.cols)
        assertEquals(130, screen.rows)
        val fit = fitAtDeviceWidth(320)
        assertTrue("fit $fit", fit < 0.2f)
        assertTrue("fit $fit", fit > 0f)
        assertRenders("terminal-320-columns") { page(TerminalViewModel.fixed("t-mac", screen)) }
    }

    @Test
    fun rendersWideCharacters() {
        assertRenders("terminal-wide") { page(TerminalViewModel.fixed("t-notes", screen(DemoTerminalScreens.WIDE))) }
    }

    @Test
    fun rendersAnAgentsTerminal() {
        assertRenders("terminal-agent") { page(TerminalViewModel.fixed("t-claude", screen(DemoTerminalScreens.AGENT))) }
    }

    @Test
    fun rendersTheMacTooOldPlaceholder() {
        assertRenders("terminal-needs-update") { page(TerminalViewModel.fixed("t-zsh", phase = TerminalViewPhase.Unsupported)) }
    }

    /** The five pages shown while the terminal cannot be drawn, by name. */
    private fun states(): List<Pair<String, TerminalViewModel>> = listOf(
        "terminal-connecting" to TerminalViewModel.fixed("t", phase = TerminalViewPhase.Connecting),
        "terminal-offline" to TerminalViewModel.fixed("t", screen(DemoTerminalScreens.SHELL), TerminalViewPhase.Offline),
        "terminal-gone" to TerminalViewModel.fixed("t", phase = TerminalViewPhase.Unavailable(TerminalUnavailableReason.GONE)),
        "terminal-refused" to TerminalViewModel.fixed("t", phase = TerminalViewPhase.Unavailable(TerminalUnavailableReason.REFUSED)),
        "terminal-failed" to TerminalViewModel.fixed("t", phase = TerminalViewPhase.Unavailable(TerminalUnavailableReason.FAILED)),
    )

    private fun rendersState(name: String) {
        val model = states().first { it.first == name }.second
        assertRenders(name) { page(model) }
    }

    @Test
    fun rendersConnecting() = rendersState("terminal-connecting")

    @Test
    fun rendersOffline() = rendersState("terminal-offline")

    @Test
    fun rendersGone() = rendersState("terminal-gone")

    @Test
    fun rendersRefused() = rendersState("terminal-refused")

    @Test
    fun rendersFailed() = rendersState("terminal-failed")

    @Test
    fun theFiveStatesLookDifferent() {
        val firsts = states().map { (name, model) ->
            ShellXSnapshots.capture(name) {
                CompositionLocalProvider(LocalSpinner provides StillSpinner) { page(model) }
            }.first { it.theme == "light" && it.language == "en" }.argb
        }
        for (i in firsts.indices) {
            for (j in i + 1 until firsts.size) {
                assertTrue("${states()[i].first} and ${states()[j].first} look different", !firsts[i].contentEquals(firsts[j]))
            }
        }
    }
}
