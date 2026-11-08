import Foundation
import ShellXLinkCore

/// A terminal's content as the demo Mac serves it: what `FakeMac` shows for a terminal, and what the render tests draw.
public struct DemoTerminalFixture: Equatable, Sendable {
    public var cols: Int
    public var rows: Int
    public var alt: Bool
    public var palette: TerminalPalette
    public var styles: [TerminalStyle]
    /// History rows, oldest first (main screen only).
    public var history: [[TerminalRun]]
    /// Screen rows from the top; rows past the end are blank.
    public var screen: [[TerminalRun]]
    public var cursor: TerminalCursor
    /// A shell: `screen[cursor.y]` is this prompt, typing is echoed after it, Enter starts a new prompt row.
    /// Nil: input changes nothing.
    public var prompt: [TerminalRun]?
    /// Printed one after the other at the cursor while the terminal is viewed, every `tickInterval`.
    public var ticks: [[TerminalRun]]
    public var tickInterval: Duration?

    public init(
        cols: Int, rows: Int, alt: Bool = false, palette: TerminalPalette = DemoTerminalScreens.palette,
        styles: [TerminalStyle] = DemoTerminalScreens.styles, history: [[TerminalRun]] = [],
        screen: [[TerminalRun]], cursor: TerminalCursor, prompt: [TerminalRun]? = nil,
        ticks: [[TerminalRun]] = [], tickInterval: Duration? = nil
    ) {
        self.cols = cols
        self.rows = rows
        self.alt = alt
        self.palette = palette
        self.styles = styles
        self.history = history
        self.screen = screen
        self.cursor = cursor
        self.prompt = prompt
        self.ticks = ticks
        self.tickInterval = tickInterval
    }

    /// The content as one snapshot: head (`.snapshot`, cols, rows, alt, cursor, palette, history = alt ? 0 : history.count),
    /// every style, history rows at y = -history.count ... -1 (none on the alternate screen), then each non-empty screen row at its y.
    public var snapshot: TerminalGridFrame {
        let kept = alt ? [] : history
        var lines: [TerminalLine] = kept.enumerated().map { index, runs in TerminalLine(y: index - kept.count, runs: runs) }
        for (y, runs) in screen.enumerated() where y < rows && !runs.isEmpty { lines.append(TerminalLine(y: y, runs: runs)) }
        return TerminalGridFrame(
            head: TerminalFrameHead(
                kind: .snapshot, cols: cols, rows: rows, alt: alt, cursor: cursor, palette: palette, history: kept.count),
            styles: styles, lines: lines)
    }
}

/// The demo's terminal content: a palette, a style table, a small markup for rows, and the fixtures.
public enum DemoTerminalScreens {
    /// The 16 base colours of the demo palette.
    private static let base = [
        "#1b1a23", "#e88a8a", "#6fd49a", "#e8c468", "#60a5fa", "#c792ea", "#7fd6e0", "#d0cde0",
        "#4a4858", "#f2a7a7", "#93e3b5", "#f0d68f", "#8bbefc", "#d9b0f0", "#a3e6ee", "#f5f3fa",
    ]

    public static let palette = TerminalPalette(fg: "#e6e3f0", bg: "#0b0716", cursor: "#60a5fa", colors: xterm256(base: base))

    public static let styles: [TerminalStyle] = [
        TerminalStyle(id: 1, fg: 2, attrs: [.bold]),
        TerminalStyle(id: 2, fg: 6, attrs: [.bold]),
        TerminalStyle(id: 3, attrs: [.faint]),
        TerminalStyle(id: 4, fg: 1),
        TerminalStyle(id: 5, fg: 3),
        TerminalStyle(id: 6, fg: 4),
        TerminalStyle(id: 7, attrs: [.inverse]),
        TerminalStyle(id: 8, fg: 0, bg: 6),
        TerminalStyle(id: 9, fg: 8, attrs: [.italic]),
        TerminalStyle(id: 10, fg: 5),
        TerminalStyle(id: 11, fgRgb: "#ff8800"),
        TerminalStyle(id: 12, fg: 12, attrs: [.underline]),
        TerminalStyle(id: 13, attrs: [.strike]),
    ]

    /// The 16 given colours, then the 6×6×6 cube (levels 0, 95, 135, 175, 215, 255; index 16 + 36r + 6g + b), then 24 greys
    /// (8 + 10·i, index 232 + i), each "#rrggbb" in lowercase.
    public static func xterm256(base: [String]) -> [String] {
        func hex(_ r: Int, _ g: Int, _ b: Int) -> String { String(format: "#%02x%02x%02x", r, g, b) }
        let levels = [0, 95, 135, 175, 215, 255]
        var colors = Array(base.prefix(16))
        while colors.count < 16 { colors.append("#000000") }
        for r in 0..<6 { for g in 0..<6 { for b in 0..<6 { colors.append(hex(levels[r], levels[g], levels[b])) } } }
        for i in 0..<24 { colors.append(hex(8 + 10 * i, 8 + 10 * i, 8 + 10 * i)) }
        return colors
    }

    /// Runs from markup: "{n}" (one or more ASCII digits between braces) switches to style n for what follows ("{0}": the
    /// default style, `style` nil); any other "{" is text. Each Character whose first scalar is East Asian wide (U+1100-115F,
    /// U+2E80-303E, U+3041-33FF, U+3400-4DBF, U+4E00-9FFF, U+A000-A4CF, U+AC00-D7A3, U+F900-FAFF, U+FE30-FE4F, U+FF00-FF60,
    /// U+FFE0-FFE6, U+20000-3FFFD) or has `properties.isEmojiPresentation` is its own run with `width` 2; any other Character
    /// of more than one scalar is its own run with `width` 1; the rest of a same-style stretch is one narrow run. No run has `x`.
    public static func runs(_ markup: String) -> [TerminalRun] {
        var result: [TerminalRun] = []
        var style: Int?
        var stretch = ""
        func flush() {
            if !stretch.isEmpty { result.append(TerminalRun(text: stretch, style: style)) }
            stretch = ""
        }
        let characters = Array(markup)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "{", let (number, next) = styleSwitch(characters, at: index) {
                flush()
                style = number == 0 ? nil : number
                index = next
                continue
            }
            let scalars = character.unicodeScalars
            if let first = scalars.first, isWide(first) {
                flush()
                result.append(TerminalRun(text: String(character), style: style, width: 2))
            } else if scalars.count > 1 {
                flush()
                result.append(TerminalRun(text: String(character), style: style, width: 1))
            } else {
                stretch.append(character)
            }
            index += 1
        }
        flush()
        return result
    }

    /// The style number of a "{digits}" at `index` and the index after its "}", or nil.
    private static func styleSwitch(_ characters: [Character], at index: Int) -> (Int, Int)? {
        var end = index + 1
        var digits = ""
        while end < characters.count, let ascii = characters[end].asciiValue, ascii >= 0x30, ascii <= 0x39 {
            digits.append(characters[end])
            end += 1
        }
        guard !digits.isEmpty, end < characters.count, characters[end] == "}", let number = Int(digits) else { return nil }
        return (number, end + 1)
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD,
    ]

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiPresentation || wideRanges.contains { $0.contains(scalar.value) }
    }

    /// Columns `runs` take: a run with a width is one cell of that width, any other one column per scalar.
    static func columns(_ runs: [TerminalRun]) -> Int {
        runs.reduce(0) { $0 + ($1.width ?? $1.text.unicodeScalars.count) }
    }

    /// `runs(prefix + spaces + suffix)`, with as many spaces as bring `prefix` to `column` columns.
    private static func padded(_ prefix: String, to column: Int, then suffix: String = "") -> [TerminalRun] {
        let spaces = max(0, column - columns(runs(prefix)))
        return runs(prefix + String(repeating: " ", count: spaces) + suffix)
    }

    private static func bars(_ count: Int) -> String { String(repeating: "|", count: count) }
    private static func spaces(_ count: Int) -> String { String(repeating: " ", count: count) }

    // MARK: - Fixtures

    /// The shell prompt of `shell` (23 columns).
    private static let shellPrompt = "{1}➜ {2}shellx {5}git:(develop){0} "
    /// The shell prompt of `wide` (8 columns).
    private static let notesPrompt = "{1}➜ {2}notes{0} "

    public static let shell: DemoTerminalFixture = {
        let p = shellPrompt
        let history = [
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
        ] + (1...17).map { "{3}[\($0)/17] Compiling ShellXLinkCore{0}" } + [
            "{1}✔{0} Executed 412 tests, with 0 failures",
            p + "clear",
            "",
        ]
        let screen = [
            p + "git status",
            "On branch develop",
            "Changes not staged for commit:",
            "  {4}modified:   UI/TerminalPane.swift{0}",
            "Untracked files:",
            "  {4}UI/TerminalKeyBar.swift{0}",
            "",
            p + "echo $TERM",
            "xterm-ghostty",
            "{9}italic{0} {13}strike{0} {12}link{0} {11}#ff8800{0} {7}inverse{0}",
            p,
        ]
        return DemoTerminalFixture(
            cols: 50, rows: 40, history: history.map(runs), screen: screen.map(runs), cursor: TerminalCursor(x: 23, y: 10),
            prompt: runs(p))
    }()

    /// A delta on `shell`: row 10 becomes its prompt + "ls -la", cursor (29, 10).
    public static let shellTyping = TerminalGridFrame(
        head: TerminalFrameHead(kind: .delta, cols: 50, rows: 40, cursor: TerminalCursor(x: 29, y: 10)),
        styles: styles,
        lines: [TerminalLine(y: 10, runs: runs(shellPrompt) + [TerminalRun(text: "ls -la")])])

    public static let devServer = DemoTerminalFixture(
        cols: 50, rows: 40,
        screen: [
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
        ].map(runs),
        cursor: TerminalCursor(x: 0, y: 10),
        ticks: [
            "{3}10:43:00{0} GET /api/status {1}200{0} in 5ms",
            "{3}10:43:03{0} GET /api/workspaces {1}200{0} in 12ms",
            "{3}10:43:06{0} POST /api/terminal {5}302{0} in 7ms",
            "{3}10:43:09{0} GET /missing {4}404{0} in 1ms",
        ].map(runs),
        tickInterval: .seconds(3))

    public static let wide = DemoTerminalFixture(
        cols: 50, rows: 40,
        screen: [
            notesPrompt + "cat ghi-chu.txt",
            // Precomposed letters (one scalar each).
            "Ti\u{1EBF}ng Vi\u{1EC7}t c\u{F3} d\u{1EA5}u: \u{1EAF} \u{1EB7} \u{1EC1} \u{1ED5} \u{1EEF} \u{111} \u{110}",
            // Combining marks.
            "D\u{1EA5}u r\u{1EDD}i: e\u{301} a\u{300} o\u{303}",
            "中文：终端测试",
            "日本語：ターミナル",
            "한국어: 터미널",
            "Emoji: 🚀 ✅ 👍🏽 🇻🇳 👨‍👩‍👧",
            notesPrompt,
        ].map(runs),
        cursor: TerminalCursor(x: 8, y: 7),
        prompt: runs(notesPrompt))

    public static let vim = DemoTerminalFixture(
        cols: 50, rows: 40, alt: true,
        screen: [
            "{10}import{0} SwiftUI",
            "",
            "{10}struct{0} ContentView: View {",
            "    {10}var{0} body: {10}some{0} View {",
            "        Text({5}\"Xin ch\u{E0}o\"{0})",
            "            .padding()",
            "    }",
            "}",
            "",
            "{9}// M\u{1EDF} trong vim tr\u{EA}n Mac{0}",
        ].map(runs)
            + Array(repeating: runs("{6}~{0}"), count: 29)
            + [runs("{7}ContentView.swift [+]" + spaces(13) + "5,9" + spaces(10) + "All{0}")],
        cursor: TerminalCursor(x: 8, y: 4, shape: .block))

    public static let htop: DemoTerminalFixture = {
        func cpu(_ number: Int, green: Int, red: Int, _ percent: String, then rest: String) -> String {
            "  {6}\(number){0}  [{1}" + bars(green) + "{4}" + bars(red) + "{0}" + spaces(30 - green - red) + percent + "]"
                + (rest.isEmpty ? "" : "   " + rest)
        }
        let processes = [
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
        ]
        let header = "    PID USER       PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command"
        let selected = 12 - 8
        var screen: [[TerminalRun]] = [
            runs(cpu(1, green: 9, red: 2, "38.2%", then: "{6}Tasks:{0} 214, 1203 thr; 3 running")),
            runs(cpu(2, green: 3, red: 1, "12.0%", then: "{6}Load average:{0} 1.42 1.37 1.30")),
            runs(cpu(3, green: 12, red: 4, "51.7%", then: "{6}Uptime:{0} 3 days, 04:12:55")),
            runs(cpu(4, green: 2, red: 0, " 6.1%", then: "")),
            runs("  {6}Mem{0}[{1}" + bars(11) + "{6}" + bars(2) + "{5}" + bars(2) + "{0}" + spaces(9) + "9.81G/16.0G]"),
            runs("  {6}Swp{0}[{4}" + bars(1) + "{0}" + spaces(24) + "112M/2.00G]"),
            [],
            padded("{8}" + header, to: 100, then: "{0}"),
        ]
        for (index, process) in processes.enumerated() {
            screen.append(index == selected ? padded("{7}" + process, to: 100, then: "{0}") : runs(process))
        }
        screen.append([])
        screen.append(runs(
            "{7}F1{0}Help  {7}F2{0}Setup {7}F3{0}Search{7}F4{0}Filter{7}F5{0}Tree  {7}F6{0}SortBy{7}F7{0}Nice -"
                + "{7}F8{0}Nice +{7}F9{0}Kill  {7}F10{0}Quit"))
        return DemoTerminalFixture(
            cols: 100, rows: 30, alt: true, screen: screen, cursor: TerminalCursor(x: 0, y: 29, visible: false))
    }()

    public static let agent: DemoTerminalFixture = {
        let line = String(repeating: "─", count: 48)
        let top = runs("{6}╭" + line + "╮{0}")
        let bottom = runs("{6}╰" + line + "╯{0}")
        var screen: [[TerminalRun]] = [
            top,
            padded("{6}│{0} {1}✻{0} Agent \u{111}ang l\u{E0}m vi\u{1EC7}c \u{1EDF} shellx-ios", to: 49, then: "{6}│{0}"),
            bottom,
            [],
            runs("{1}●{0} \u{110}\u{1ECD}c UI/Terminal/TerminalPane.swift"),
            runs("{1}●{0} S\u{1EED}a 3 t\u{1EC7}p, ch\u{1EA1}y {5}swift test{0}"),
            runs("  {3}⎿ Executed 128 tests, with 0 failures{0}"),
            [],
            runs("Xong ph\u{1EA7}n v\u{1EBD} terminal. Ti\u{1EBF}p theo: b\u{E0}n ph\u{ED}m."),
        ]
        screen += Array(repeating: [], count: 36 - screen.count)
        screen += [top, padded("{6}│{0} > ", to: 49, then: "{6}│{0}"), bottom]
        screen.append(runs("  {3}Enter g\u{1EED}i · Esc d\u{1EEB}ng{0}"))
        return DemoTerminalFixture(cols: 50, rows: 40, alt: true, screen: screen, cursor: TerminalCursor(x: 4, y: 37))
    }()

    /// A fresh shell: row 0 is runs("{1}$ "), cursor (2, 0), that row is the prompt.
    public static func prompt(cols: Int, rows: Int) -> DemoTerminalFixture {
        let prompt = runs("{1}$ ")
        return DemoTerminalFixture(cols: cols, rows: rows, screen: [prompt], cursor: TerminalCursor(x: 2, y: 0), prompt: prompt)
    }
}
