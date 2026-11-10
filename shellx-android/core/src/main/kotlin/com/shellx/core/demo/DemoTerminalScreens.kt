package com.shellx.core.demo

import com.shellx.core.text.graphemes
import com.shellx.link.core.TerminalAttribute
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalFrameHead
import com.shellx.link.core.TerminalFrameKind
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalLine
import com.shellx.link.core.TerminalPalette
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalStyle
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** A terminal's content as the demo Mac serves it: what [FakeMac] shows for a terminal, and what the render tests draw. */
data class DemoTerminalFixture(
    val cols: Int,
    val rows: Int,
    val alt: Boolean = false,
    val palette: TerminalPalette = DemoTerminalScreens.PALETTE,
    val styles: List<TerminalStyle> = DemoTerminalScreens.STYLES,
    /** History rows, oldest first (main screen only). */
    val history: List<List<TerminalRun>> = emptyList(),
    /** Screen rows from the top; rows past the end are blank. */
    val screen: List<List<TerminalRun>>,
    val cursor: TerminalCursor,
    /** A shell: `screen[cursor.y]` is this prompt, typing is echoed after it, Enter starts a new prompt row. Null: input
     *  changes nothing. */
    val prompt: List<TerminalRun>? = null,
    /** Printed one after the other at the cursor while the terminal is viewed, every [tickInterval]. */
    val ticks: List<List<TerminalRun>> = emptyList(),
    val tickInterval: Duration? = null,
) {
    /**
     * The content as one snapshot: head (SNAPSHOT, cols, rows, alt, cursor, palette, history = alt ? 0 : history.size),
     * every style, history rows at y = -history.size … -1 (none on the alternate screen), then each non-empty screen row
     * at its y.
     */
    val snapshot: TerminalGridFrame
        get() {
            val kept = if (alt) emptyList() else history
            val lines = ArrayList<TerminalLine>(kept.size + screen.size)
            kept.forEachIndexed { index, runs -> lines += TerminalLine(index - kept.size, runs) }
            screen.forEachIndexed { y, runs -> if (y < rows && runs.isNotEmpty()) lines += TerminalLine(y, runs) }
            return TerminalGridFrame(
                TerminalFrameHead(
                    TerminalFrameKind.SNAPSHOT, cols, rows, alt = alt, cursor = cursor, palette = palette,
                    history = kept.size,
                ),
                styles, lines,
            )
        }
}

/** The demo's terminal content (DemoTerminalScreens.swift): a palette, a style table, a small markup for rows, and the fixtures. */
object DemoTerminalScreens {
    /** The 16 base colours of the demo palette. */
    private val BASE = listOf(
        "#1b1a23", "#e88a8a", "#6fd49a", "#e8c468", "#60a5fa", "#c792ea", "#7fd6e0", "#d0cde0",
        "#4a4858", "#f2a7a7", "#93e3b5", "#f0d68f", "#8bbefc", "#d9b0f0", "#a3e6ee", "#f5f3fa",
    )

    val PALETTE: TerminalPalette = TerminalPalette("#e6e3f0", "#0b0716", cursor = "#60a5fa", colors = xterm256(BASE))

    val STYLES: List<TerminalStyle> = listOf(
        TerminalStyle(1, fg = 2, attrs = listOf(TerminalAttribute.BOLD)),
        TerminalStyle(2, fg = 6, attrs = listOf(TerminalAttribute.BOLD)),
        TerminalStyle(3, attrs = listOf(TerminalAttribute.FAINT)),
        TerminalStyle(4, fg = 1),
        TerminalStyle(5, fg = 3),
        TerminalStyle(6, fg = 4),
        TerminalStyle(7, attrs = listOf(TerminalAttribute.INVERSE)),
        TerminalStyle(8, fg = 0, bg = 6),
        TerminalStyle(9, fg = 8, attrs = listOf(TerminalAttribute.ITALIC)),
        TerminalStyle(10, fg = 5),
        TerminalStyle(11, fgRgb = "#ff8800"),
        TerminalStyle(12, fg = 12, attrs = listOf(TerminalAttribute.UNDERLINE)),
        TerminalStyle(13, attrs = listOf(TerminalAttribute.STRIKE)),
    )

    /**
     * The 16 given colours, then the 6×6×6 cube (levels 0, 95, 135, 175, 215, 255; index 16 + 36r + 6g + b), then 24
     * greys (8 + 10·i, index 232 + i), each "#rrggbb" in lowercase.
     */
    fun xterm256(base: List<String>): List<String> {
        fun hex(r: Int, g: Int, b: Int) = "#%02x%02x%02x".format(r, g, b)
        val levels = listOf(0, 95, 135, 175, 215, 255)
        val colors = ArrayList<String>(256)
        colors += base.take(16)
        while (colors.size < 16) colors += "#000000"
        for (r in 0 until 6) for (g in 0 until 6) for (b in 0 until 6) colors += hex(levels[r], levels[g], levels[b])
        for (i in 0 until 24) colors += hex(8 + 10 * i, 8 + 10 * i, 8 + 10 * i)
        return colors
    }

    /**
     * Runs from markup: "{n}" (one or more ASCII digits between braces) switches to style n for what follows ("{0}": the
     * default style, `style` null); any other "{" is text. Each grapheme whose first code point is East Asian wide
     * (U+1100-115F, U+2E80-303E, U+3041-33FF, U+3400-4DBF, U+4E00-9FFF, U+A000-A4CF, U+AC00-D7A3, U+F900-FAFF,
     * U+FE30-FE4F, U+FF00-FF60, U+FFE0-FFE6, U+20000-3FFFD) or an emoji shown as one ([isEmojiPresentation]) is its own
     * run with `width` 2; any other grapheme of more than one code point is its own run with `width` 1; the rest of a
     * same-style stretch is one narrow run. No run has `x`.
     */
    fun runs(markup: String): List<TerminalRun> {
        val result = ArrayList<TerminalRun>()
        var style: Int? = null
        val stretch = StringBuilder()
        fun flush() {
            if (stretch.isNotEmpty()) result += TerminalRun(text = stretch.toString(), style = style)
            stretch.setLength(0)
        }
        val characters = markup.graphemes()
        var index = 0
        while (index < characters.size) {
            val character = characters[index]
            val switch = if (character == "{") styleSwitch(characters, index) else null
            if (switch != null) {
                flush()
                style = switch.first.takeIf { it != 0 }
                index = switch.second
                continue
            }
            val first = character.codePointAt(0)
            when {
                isWide(first) -> {
                    flush()
                    result += TerminalRun(text = character, style = style, width = 2)
                }
                character.codePointCount(0, character.length) > 1 -> {
                    flush()
                    result += TerminalRun(text = character, style = style, width = 1)
                }
                else -> stretch.append(character)
            }
            index += 1
        }
        flush()
        return result
    }

    /** The style number of a "{digits}" at [index] and the index after its "}", or null. */
    private fun styleSwitch(characters: List<String>, index: Int): Pair<Int, Int>? {
        var end = index + 1
        val digits = StringBuilder()
        while (end < characters.size && characters[end].length == 1 && characters[end][0] in '0'..'9') {
            digits.append(characters[end])
            end += 1
        }
        if (digits.isEmpty() || end >= characters.size || characters[end] != "}") return null
        val number = digits.toString().toIntOrNull() ?: return null
        return number to end + 1
    }

    private val WIDE_RANGES: List<IntRange> = listOf(
        0x1100..0x115F, 0x2E80..0x303E, 0x3041..0x33FF, 0x3400..0x4DBF, 0x4E00..0x9FFF, 0xA000..0xA4CF,
        0xAC00..0xD7A3, 0xF900..0xFAFF, 0xFE30..0xFE4F, 0xFF00..0xFF60, 0xFFE0..0xFFE6, 0x20000..0x3FFFD,
    )

    /** Swift's `isEmojiPresentation` for what the fixtures use: Java 17 has no such property (plan 3G Task 5). */
    private val EMOJI_RANGES: List<IntRange> = listOf(
        0x1F1E6..0x1F1FF, 0x1F300..0x1F64F, 0x1F680..0x1F6FF, 0x1F900..0x1F9FF, 0x1FA70..0x1FAFF,
    )

    private val EMOJI: Set<Int> = buildSet {
        addAll(listOf(0x231A, 0x231B, 0x23F0, 0x23F3, 0x25FD, 0x25FE, 0x2614, 0x2615, 0x267F, 0x2693, 0x26A1))
        addAll(listOf(0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4, 0x26EA, 0x26F2, 0x26F3))
        addAll(listOf(0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B, 0x2728, 0x274C, 0x274E, 0x2757, 0x27B0))
        addAll(listOf(0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55))
        addAll(0x23E9..0x23EC)
        addAll(0x2648..0x2653)
        addAll(0x2753..0x2755)
        addAll(0x2795..0x2797)
    }

    private fun isEmojiPresentation(codePoint: Int): Boolean =
        codePoint in EMOJI || EMOJI_RANGES.any { codePoint in it }

    private fun isWide(codePoint: Int): Boolean = isEmojiPresentation(codePoint) || WIDE_RANGES.any { codePoint in it }

    /** Columns [runs] take: a run with a width is one cell of that width, any other one column per code point. */
    internal fun columns(runs: List<TerminalRun>): Int = runs.sumOf { it.width ?: it.text.codePointCount(0, it.text.length) }

    /** `runs(prefix + spaces + suffix)`, with as many spaces as bring [prefix] to [column] columns. */
    private fun padded(prefix: String, column: Int, suffix: String = ""): List<TerminalRun> =
        runs(prefix + spaces(maxOf(0, column - columns(runs(prefix)))) + suffix)

    private fun bars(count: Int) = "|".repeat(count)

    private fun spaces(count: Int) = " ".repeat(count)

    // Fixtures

    /** The shell prompt of [SHELL] (23 columns). */
    private const val SHELL_PROMPT = "{1}➜ {2}shellx {5}git:(develop){0} "

    /** The shell prompt of [WIDE] (8 columns). */
    private const val NOTES_PROMPT = "{1}➜ {2}notes{0} "

    val SHELL: DemoTerminalFixture = run {
        val p = SHELL_PROMPT
        val history = listOf(
            p + "git log --oneline -6",
            "{5}d0a26e2{0} docs: specs for sign-in and terminal",
            "{5}df63759{0} release: point the website at 1.7.0",
            "{5}f904210{0} build: ShellX for Windows 1.7.0",
            "{5}46f99e7{0} build: ShellX 1.7.0 (build 123)",
            "{5}fd510af{0} merge: automation flowchart",
            "{5}0d6c8af{0} fix: keep the selection on the Mac",
            p + "ls",
            "{2}Packages{0}   README.md   {2}shellx-ios{0}   {2}shellx-link{0}",
            p + "swift test",
        ) + (1..17).map { "{3}[$it/17] Compiling ShellXLinkCore{0}" } + listOf(
            "{1}✔{0} Executed 412 tests, with 0 failures",
            p + "clear",
            "",
        )
        val screen = listOf(
            p + "git status",
            "On branch develop",
            "Changes not staged for commit:",
            "  {4}modified:   UI/TerminalPane.swift{0}",
            "Untracked files:",
            "  {4}UI/TerminalKeyBar.swift{0}",
            "",
            p + "echo \$TERM",
            "xterm-ghostty",
            "{9}italic{0} {13}strike{0} {12}link{0} {11}#ff8800{0} {7}inverse{0}",
            p,
        )
        DemoTerminalFixture(
            cols = 50, rows = 40, history = history.map(::runs), screen = screen.map(::runs),
            cursor = TerminalCursor(23, 10), prompt = runs(p),
        )
    }

    /** A delta on [SHELL]: row 10 becomes its prompt + "ls -la", cursor (29, 10). */
    val SHELL_TYPING: TerminalGridFrame = TerminalGridFrame(
        TerminalFrameHead(TerminalFrameKind.DELTA, 50, 40, cursor = TerminalCursor(29, 10)),
        STYLES,
        listOf(TerminalLine(10, runs(SHELL_PROMPT) + TerminalRun(text = "ls -la"))),
    )

    val DEV_SERVER: DemoTerminalFixture = DemoTerminalFixture(
        cols = 50, rows = 40,
        screen = listOf(
            "{3}> web@0.1.0 dev{0}",
            "{3}> dev-server --port 3000{0}",
            "",
            "  {1}DEV{0} server ready in {5}412 ms{0}",
            "  {1}➜{0}  Local:   {12}http://localhost:3000/{0}",
            "  {1}➜{0}  Network: {3}use --host to expose{0}",
            "",
            "{3}10:42:01{0} GET / {1}200{0} in 23ms",
            "{3}10:42:02{0} GET /api/status {1}200{0} in 4ms",
            "{3}10:42:05{0} GET /favicon.ico {4}404{0} in 2ms",
        ).map(::runs),
        cursor = TerminalCursor(0, 10),
        ticks = listOf(
            "{3}10:43:00{0} GET /api/status {1}200{0} in 5ms",
            "{3}10:43:03{0} GET /api/workspaces {1}200{0} in 12ms",
            "{3}10:43:06{0} POST /api/terminal {5}302{0} in 7ms",
            "{3}10:43:09{0} GET /missing {4}404{0} in 1ms",
        ).map(::runs),
        tickInterval = 3.seconds,
    )

    val WIDE: DemoTerminalFixture = DemoTerminalFixture(
        cols = 50, rows = 40,
        screen = listOf(
            NOTES_PROMPT + "cat ghi-chu.txt",
            // Precomposed letters (one code point each).
            "Tiếng Việt có dấu: ắ ặ ề ổ ữ đ Đ",
            // Combining marks.
            "Dấu rời: é à õ",
            "中文：终端测试",
            "日本語：ターミナル",
            "한국어: 터미널",
            "Emoji: 🚀 ✅ 👍🏽 🇻🇳 👨‍👩‍👧",
            NOTES_PROMPT,
        ).map(::runs),
        cursor = TerminalCursor(8, 7),
        prompt = runs(NOTES_PROMPT),
    )

    val VIM: DemoTerminalFixture = DemoTerminalFixture(
        cols = 50, rows = 40, alt = true,
        screen = listOf(
            "{10}import{0} SwiftUI",
            "",
            "{10}struct{0} ContentView: View {",
            "    {10}var{0} body: {10}some{0} View {",
            "        Text({5}\"Xin chào\"{0})",
            "            .padding()",
            "    }",
            "}",
            "",
            "{9}// Mở trong vim trên Mac{0}",
        ).map(::runs) +
            List(29) { runs("{6}~{0}") } +
            listOf(runs("{7}ContentView.swift [+]" + spaces(13) + "5,9" + spaces(10) + "All{0}")),
        cursor = TerminalCursor(8, 4, shape = com.shellx.link.core.TerminalCursorShape.BLOCK),
    )

    val HTOP: DemoTerminalFixture = run {
        fun cpu(number: Int, green: Int, red: Int, percent: String, rest: String): String =
            "  {6}$number{0}  [{1}" + bars(green) + "{4}" + bars(red) + "{0}" + spaces(30 - green - red) + percent + "]" +
                (if (rest.isEmpty()) "" else "   $rest")
        val processes = listOf(
            "   4182 phu         17   0  412G 1.21G  312M S 42.7  7.6 3:41.07  ShellX",
            "   5120 phu         31   0  402G  388M   61M R 28.3  2.4 1:12.55  claude",
            "   5233 phu         24   0  401G  512M   48M S 17.9  3.2 0:58.12  node dev-server --port 3000",
            "   6011 phu         20   0  399G 1.02G   96M R 12.4  6.4 0:44.90  swift-build --build-tests",
            "    611 root         4   0  393G   42M   18M S  8.8  0.3 5:02.31  WindowServer -daemon",
            "   2210 phu         31   0  1.5T  824M  220M S  6.1  5.1 2:13.40  Safari",
            "   5121 phu         31   0  401G  9264  3120 S  3.7  0.1 0:03.18  -zsh",
            "    388 root        20   0  392G   28M  9856 S  2.9  0.2 1:47.66  /usr/libexec/logd",
            "   6020 phu         24   0  398G  644M   72M S  2.2  4.0 0:21.09  swift-frontend -c ShellXLinkCore",
            "   1402 phu         31   0  401G  210M   58M S  1.8  1.3 0:39.72  Finder",
            "   5234 phu         24   0  400G   96M   31M S  1.4  0.6 0:05.44  node esbuild --service=0.21.5",
            "    410 root        20   0  392G   14M  5232 S  1.1  0.1 0:52.08  /usr/sbin/mDNSResponder",
            "   2290 phu         31   0  401G  176M   64M S  0.9  1.1 0:17.53  com.apple.WebKit.WebContent",
            "   5122 phu         31   0  401G  8896  3008 S  0.7  0.1 0:01.02  -zsh",
            "   1203 phu         31   0  401G   64M   22M S  0.5  0.4 0:08.61  /usr/libexec/trustd",
            "   6033 phu         24   0  397G   22M  8512 S  0.4  0.1 0:00.77  git status --porcelain",
            "    912 root        20   0  392G  9472  4096 S  0.3  0.1 0:11.36  /usr/libexec/coreduetd",
            "   1500 phu         31   0  401G   48M   17M S  0.2  0.3 0:04.95  /usr/libexec/nsurlsessiond",
            "   5340 phu         31   0  401G  7680  2944 S  0.1  0.0 0:00.31  -zsh",
            "      1 root        20   0  392G   25M   12M S  0.0  0.2 2:58.04  /sbin/launchd",
        )
        val header = "    PID USER       PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command"
        val selected = 12 - 8
        val screen = mutableListOf(
            runs(cpu(1, green = 9, red = 2, "38.2%", "{6}Tasks:{0} 214, 1203 thr; 3 running")),
            runs(cpu(2, green = 3, red = 1, "12.0%", "{6}Load average:{0} 1.42 1.37 1.30")),
            runs(cpu(3, green = 12, red = 4, "51.7%", "{6}Uptime:{0} 3 days, 04:12:55")),
            runs(cpu(4, green = 2, red = 0, " 6.1%", "")),
            runs("  {6}Mem{0}[{1}" + bars(11) + "{6}" + bars(2) + "{5}" + bars(2) + "{0}" + spaces(9) + "9.81G/16.0G]"),
            runs("  {6}Swp{0}[{4}" + bars(1) + "{0}" + spaces(24) + "112M/2.00G]"),
            emptyList(),
            padded("{8}$header", 100, "{0}"),
        )
        processes.forEachIndexed { index, process ->
            screen += if (index == selected) padded("{7}$process", 100, "{0}") else runs(process)
        }
        screen += emptyList<TerminalRun>()
        screen += runs(
            "{7}F1{0}Help  {7}F2{0}Setup {7}F3{0}Search{7}F4{0}Filter{7}F5{0}Tree  {7}F6{0}SortBy{7}F7{0}Nice -" +
                "{7}F8{0}Nice +{7}F9{0}Kill  {7}F10{0}Quit",
        )
        DemoTerminalFixture(
            cols = 100, rows = 30, alt = true, screen = screen, cursor = TerminalCursor(0, 29, visible = false),
        )
    }

    val AGENT: DemoTerminalFixture = run {
        val line = "─".repeat(48)
        val top = runs("{6}╭$line╮{0}")
        val bottom = runs("{6}╰$line╯{0}")
        val screen = mutableListOf(
            top,
            padded("{6}│{0} {1}✻{0} Agent đang làm việc ở shellx-ios", 49, "{6}│{0}"),
            bottom,
            emptyList(),
            runs("{1}●{0} Đọc UI/Terminal/TerminalPane.swift"),
            runs("{1}●{0} Sửa 3 tệp, chạy {5}swift test{0}"),
            runs("  {3}⎿ Executed 128 tests, with 0 failures{0}"),
            emptyList(),
            runs("Xong phần vẽ terminal. Tiếp theo: bàn phím."),
        )
        while (screen.size < 36) screen += emptyList<TerminalRun>()
        screen += listOf(top, padded("{6}│{0} > ", 49, "{6}│{0}"), bottom)
        screen += runs("  {3}Enter gửi · Esc dừng{0}")
        DemoTerminalFixture(cols = 50, rows = 40, alt = true, screen = screen, cursor = TerminalCursor(4, 37))
    }

    /** A fresh shell: row 0 is runs("{1}$ "), cursor (2, 0), that row is the prompt. */
    fun prompt(cols: Int, rows: Int): DemoTerminalFixture {
        val prompt = runs("{1}$ ")
        return DemoTerminalFixture(cols = cols, rows = rows, screen = listOf(prompt), cursor = TerminalCursor(2, 0), prompt = prompt)
    }
}
