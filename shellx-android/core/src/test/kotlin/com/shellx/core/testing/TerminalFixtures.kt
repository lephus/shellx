package com.shellx.core.testing

import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalFramePart
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRun

/** fg #d0d0d0, bg #101010, colors[i] = grey i (`testPalette` in TerminalTestSupport.swift). */
val testPalette = TerminalPalette("#d0d0d0", "#101010", colors = (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })

private fun textLine(y: Int, text: String): TerminalLine =
    TerminalLine(y, if (text.isEmpty()) emptyList() else listOf(TerminalRun(x = 0, text = text)))

/** History lines at y = -lines.size … -1, oldest first. */
private fun historyLines(lines: List<String>): List<TerminalLine> =
    lines.mapIndexed { index, text -> textLine(index - lines.size, text) }

/**
 * One whole frame in one part (part 0 of 1). Snapshot head: cursor (0, 0), [testPalette], `history` = history.size;
 * history rows at y = -history.size … -1, then `text[i]` at y = i.
 */
fun snapshotPart(
    revision: Long,
    cols: Int = 20,
    rows: Int = 2,
    text: List<String>,
    history: List<String> = emptyList(),
    alt: Boolean = false,
): TerminalFramePart {
    val head = TerminalFrameHead(
        TerminalFrameKind.SNAPSHOT, cols, rows, alt = alt, cursor = TerminalCursor(0, 0), palette = testPalette,
        history = history.size,
    )
    val lines = historyLines(history) + text.mapIndexed { y, line -> textLine(y, line) }
    return TerminalFramePart(revision, head = head, lines = lines)
}

/** A delta in one part. Head: cursor (0, 0), [scroll], `history` = history.size; `replacing[y]` at y. */
fun deltaPart(
    revision: Long,
    cols: Int = 20,
    rows: Int = 2,
    replacing: Map<Int, String>,
    scroll: Int = 0,
    history: List<String> = emptyList(),
    alt: Boolean = false,
): TerminalFramePart {
    val head = TerminalFrameHead(
        TerminalFrameKind.DELTA, cols, rows, alt = alt, cursor = TerminalCursor(0, 0), history = history.size,
        scroll = scroll,
    )
    val lines = historyLines(history) + replacing.keys.sorted().map { textLine(it, replacing.getValue(it)) }
    return TerminalFramePart(revision, head = head, lines = lines)
}

/** Older history rows in one part: [lines] (oldest first) go above the oldest row held. */
fun historyPart(revision: Long, cols: Int = 20, rows: Int = 2, lines: List<String>): TerminalFramePart {
    val head = TerminalFrameHead(TerminalFrameKind.HISTORY, cols, rows, history = lines.size)
    return TerminalFramePart(revision, head = head, lines = historyLines(lines))
}
