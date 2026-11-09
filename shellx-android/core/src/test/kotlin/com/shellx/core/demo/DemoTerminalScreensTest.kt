package com.shellx.core.demo

import com.shellx.link.core.TerminalFrameAssembler
import com.shellx.link.core.TerminalFramePart
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalScreen
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

/** The demo's terminal content: palette, markup and the fixtures the render tests and the demo Mac show. */
class DemoTerminalScreensTest {
    @Test fun xterm256() {
        val colors = DemoTerminalScreens.xterm256(List(16) { "#123456" })
        assertEquals(256, colors.size)
        assertEquals(
            listOf("#000000", "#0000ff", "#ff0000", "#ffffff", "#080808", "#eeeeee"),
            listOf(colors[16], colors[21], colors[196], colors[231], colors[232], colors[255]),
        )
        assertEquals("#60a5fa", DemoTerminalScreens.PALETTE.colors[4])
        assertEquals("#0b0716", DemoTerminalScreens.PALETTE.bg)
    }

    @Test fun markup() {
        assertEquals(listOf(TerminalRun(text = "$ ", style = 1), TerminalRun(text = "ls")), DemoTerminalScreens.runs("{1}$ {0}ls"))
        assertEquals(
            listOf(
                TerminalRun(text = "a"), TerminalRun(text = "中", width = 2), TerminalRun(text = "é", width = 1),
                TerminalRun(text = "🇻🇳", width = 2), TerminalRun(text = "{z"),
            ),
            DemoTerminalScreens.runs("a中é🇻🇳{z"),
        )
    }

    @Test fun everyFixtureSplitsAndAssemblesIntoItself() {
        for ((name, fixture) in all) {
            val snapshot = fixture.snapshot
            // No splitter on Android: the fake Mac sends each frame as one part.
            val part = TerminalFramePart(1, 0, 1, snapshot.head, snapshot.styles, snapshot.lines)
            assertEquals(snapshot, TerminalFrameAssembler().receive(part).frame, name)
            val screen = TerminalScreen()
            screen.apply(snapshot)
            assertEquals(fixture.cols, screen.cols, name)
            assertEquals(fixture.alt, screen.alt, name)
            assertEquals(if (fixture.alt) 0 else fixture.history.size, screen.historyRows.size, name)
            assertTrue(fixture.screen.size <= fixture.rows, name)
            fixture.prompt?.let { assertEquals(it, fixture.screen[fixture.cursor.y], name) }
            // No row is wider than its fixture.
            for ((index, row) in (fixture.history + fixture.screen + fixture.ticks).withIndex()) {
                assertTrue(columns(row) <= fixture.cols, "$name row $index")
            }
        }
    }

    @Test fun theFixturesHoldWhatTheRenderTestsShow() {
        assertTrue(DemoTerminalScreens.VIM.alt && DemoTerminalScreens.HTOP.alt && DemoTerminalScreens.AGENT.alt)
        assertEquals(100, DemoTerminalScreens.HTOP.cols)
        assertEquals(30, DemoTerminalScreens.SHELL.history.size)
        assertEquals(23, DemoTerminalScreens.SHELL.cursor.x)
        val wide = DemoTerminalScreens.WIDE.screen.flatten()
        assertTrue(TerminalRun(text = "中", width = 2) in wide)
        assertTrue(TerminalRun(text = "🇻🇳", width = 2) in wide)
        assertTrue(TerminalRun(text = "é", width = 1) in wide)
        assertEquals(3.seconds, DemoTerminalScreens.DEV_SERVER.tickInterval)
        assertEquals(4, DemoTerminalScreens.DEV_SERVER.ticks.size)
        // The rows with an exact width fill their fixture.
        assertEquals(50, columns(DemoTerminalScreens.VIM.screen[39]))
        assertEquals(100, columns(DemoTerminalScreens.HTOP.screen[7]))
        assertEquals(100, columns(DemoTerminalScreens.HTOP.screen[12]))
        assertEquals(50, columns(DemoTerminalScreens.AGENT.screen[1]))
        assertEquals(50, columns(DemoTerminalScreens.AGENT.screen[37]))
    }

    @Test fun fixtureCharactersHaveTheIPhoneWidths() {
        for (w in listOf("中", "：", "ー", "한", "🚀", "✅", "👍🏽", "🇻🇳", "👨‍👩‍👧")) {
            assertEquals(listOf(TerminalRun(text = w, width = 2)), DemoTerminalScreens.runs(w), w)
        }
        for (n in listOf("✔", "➜", "✻", "●", "⎿", "╭", "─", "ắ", "·")) {
            assertEquals(listOf(TerminalRun(text = n)), DemoTerminalScreens.runs(n), n)
        }
        assertEquals(listOf(TerminalRun(text = "é", width = 1)), DemoTerminalScreens.runs("é"))
    }

    private val all: List<Pair<String, DemoTerminalFixture>> = listOf(
        "shell" to DemoTerminalScreens.SHELL, "devServer" to DemoTerminalScreens.DEV_SERVER,
        "wide" to DemoTerminalScreens.WIDE, "vim" to DemoTerminalScreens.VIM, "htop" to DemoTerminalScreens.HTOP,
        "agent" to DemoTerminalScreens.AGENT, "prompt" to DemoTerminalScreens.prompt(50, 20),
    )

    /** Columns a row takes: a run with a width is one cell of that width, any other run one column per code point. */
    private fun columns(row: List<TerminalRun>): Int = row.sumOf { it.width ?: it.text.codePointCount(0, it.text.length) }
}
