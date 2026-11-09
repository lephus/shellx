package com.shellx.link.core

/** What [TerminalFrameAssembler.receive] decided about one message. */
data class TerminalAssemblyResult(
    /** A complete frame to apply now (PROTOCOL.md 11.7), or null. */
    val frame: TerminalGridFrame? = null,
    /** Send `terminal.view.resync` now (at most once per gap). */
    val resync: Boolean = false,
)

/**
 * Puts the parts of `terminal.view.frame` messages together and applies the revision rules of PROTOCOL.md 11.7
 * (`Terminal/TerminalFrameAssembler.swift`). One per view: start a fresh one at every
 * [TerminalViewPush.Opened]. Mutable, with one owner.
 */
class TerminalFrameAssembler {
    /** The revision of the last frame applied: 0 before the first snapshot. */
    var revision: Long = 0
        private set

    /** True from a gap until the next snapshot: deltas and history frames are ignored meanwhile. */
    var awaitingSnapshot: Boolean = false
        private set

    private class Partial(val revision: Long, val parts: Int, val head: TerminalFrameHead?, first: TerminalFramePart) {
        var nextPart = 1
        val styles = ArrayList(first.styles)
        val lines = ArrayList(first.lines)
    }

    private var partial: Partial? = null
    private var cols = 0
    private var rows = 0
    private var alt = false

    /** Set by [markGap] during one [receive]. */
    private var resync = false

    fun receive(part: TerminalFramePart): TerminalAssemblyResult {
        resync = false
        if (part.part == 0) {
            if (partial != null) markGap()
            partial = Partial(part.revision, part.parts, part.head, part)
        } else {
            val current = partial
            if (current == null || current.revision != part.revision || current.parts != part.parts || part.part != current.nextPart) {
                partial = null
                markGap()
                return result(null)
            }
            current.nextPart += 1
            current.styles += part.styles
            current.lines += part.lines
        }
        val current = partial
        if (current == null || current.nextPart != current.parts) return result(null)
        partial = null
        val head = current.head
        if (head == null) {
            markGap()
            return result(null)
        }
        return result(complete(TerminalGridFrame(head, current.styles, current.lines), current.revision))
    }

    /** The frame to apply, or null. */
    private fun complete(frame: TerminalGridFrame, number: Long): TerminalGridFrame? {
        val head = frame.head
        when (head.kind) {
            TerminalFrameKind.SNAPSHOT -> {
                if (number <= revision) return null
                if (head.cursor == null || head.palette == null || !sizeIsValid(head)) {
                    markGap()
                    return null
                }
                revision = number
                awaitingSnapshot = false
                cols = head.cols
                rows = head.rows
                alt = head.alt
                return frame
            }
            TerminalFrameKind.DELTA, TerminalFrameKind.HISTORY -> {
                if (awaitingSnapshot || number <= revision) return null
                val fits = revision > 0 && number == revision + 1 && sizeIsValid(head) &&
                    head.cols == cols && head.rows == rows && head.alt == alt &&
                    (head.kind != TerminalFrameKind.DELTA || head.cursor != null)
                if (!fits) {
                    markGap()
                    return null
                }
                revision = number
                return frame
            }
            else -> {
                if (awaitingSnapshot || number <= revision) return null
                markGap()
                return null
            }
        }
    }

    private fun result(frame: TerminalGridFrame?) = TerminalAssemblyResult(frame, resync)

    private fun markGap() {
        if (awaitingSnapshot) return
        awaitingSnapshot = true
        resync = true
    }

    private fun sizeIsValid(head: TerminalFrameHead): Boolean =
        head.cols in 1..ShellXLink.TERMINAL_MAX_GRID_SIZE && head.rows in 1..ShellXLink.TERMINAL_MAX_GRID_SIZE
}
