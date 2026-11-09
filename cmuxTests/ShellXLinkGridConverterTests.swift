import CMUXMobileCore
import Foundation
import ShellXLinkCore
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("ShellX Link grid converter")
struct ShellXLinkGridConverterTests {
    typealias Span = MobileTerminalRenderGridFrame.RowSpan

    let theme = TerminalTheme(
        background: "#101010", foreground: "#D0D0D0", cursor: "#FF8800",
        selectionBackground: "#333333", selectionForeground: "#FFFFFF",
        palette: (0..<256).map { String(format: "#%02X%02X%02X", $0, $0, $0) }
    )
    var converter: ShellXLinkGridConverter { ShellXLinkGridConverter(theme: theme) }

    func span(_ column: Int, _ text: String, width: Int? = nil, style: Int = 0, row: Int = 0) -> Span {
        Span(row: row, column: column, styleID: style, text: text, cellWidth: width)
    }

    @Test func narrowSpansAreNarrowRunsAndAContiguousRunOmitsItsColumn() {
        #expect(converter.runs(
            of: [span(0, "ls", width: 2), span(2, " -la", width: 4, style: 1), span(10, "x", width: 1)],
            styles: [1: TerminalStyle(id: 1, fg: 2)]
        ) == [TerminalRun(text: "ls"), TerminalRun(text: " -la", style: 1), TerminalRun(x: 10, text: "x")])
    }

    @Test func aWideCharacterIsOneCellTwoColumnsWide() {
        #expect(converter.runs(of: [span(3, "中", width: 2)], styles: [:]) == [TerminalRun(x: 3, text: "中", width: 2)])
    }

    @Test func aCombiningMarkStaysInItsCell() {
        #expect(converter.runs(of: [span(0, "e\u{301}", width: 1)], styles: [:])
            == [TerminalRun(text: "e\u{301}", width: 1)])
    }

    @Test(arguments: [("ab", nil as Int?), ("\u{1F1FB}\u{1F1F3}", 2), ("\u{2764}\u{FE0F}", 2)])
    func twoScalarsOverTwoColumns(text: String, cellWidth: Int?) {
        #expect(converter.runs(of: [span(0, text, width: 2)], styles: [:]) == [TerminalRun(text: text, width: cellWidth)])
    }

    @Test func aClusterOver32BytesIsCutOnAScalarBoundary() throws {
        let long = "e" + String(repeating: "\u{301}", count: 20)
        let run = try #require(converter.runs(of: [span(0, long, width: 1)], styles: [:]).first)
        #expect(run.text == "e" + String(repeating: "\u{301}", count: 15) && run.width == 1)
    }

    @Test func colorsAreThoseTheMacDraws() {
        typealias S = MobileTerminalRenderGridFrame.Style
        #expect(converter.style(S(id: 1, foreground: "#020202", foregroundSource: .palette, foregroundPaletteIndex: 2))
            == TerminalStyle(id: 1, fg: 2))
        #expect(converter.style(S(id: 2, foreground: "#0A0A0A", foregroundSource: .palette, foregroundPaletteIndex: 2, bold: true))
            == TerminalStyle(id: 2, fgRgb: "#0a0a0a", attrs: [.bold]))
        #expect(converter.style(S(id: 3, foreground: "#A6E22E", background: "#336699", foregroundSource: .rgb, backgroundSource: .rgb))
            == TerminalStyle(id: 3, fgRgb: "#a6e22e", bgRgb: "#336699"))
        #expect(converter.style(S(id: 4, foreground: "#FFFFFF", foregroundSource: .defaultColor, bold: true))
            == TerminalStyle(id: 4, fgRgb: "#ffffff", attrs: [.bold]))
        #expect(converter.style(S(id: 5, foreground: "#D0D0D0", background: "#101010",
                                  foregroundSource: .defaultColor, backgroundSource: .defaultColor)) == nil)
        #expect(converter.style(S(id: 6, background: "#040404", backgroundSource: .palette, backgroundPaletteIndex: 4))
            == TerminalStyle(id: 6, bg: 4))
        #expect(converter.style(S(id: 7, bold: true, faint: true, italic: true, underline: true, blink: true, inverse: true,
                                  invisible: true, strikethrough: true, overline: true))?.attrs
            == [.bold, .faint, .italic, .underline, .blink, .inverse, .invisible, .strike, .overline])
        #expect(converter.style(S(id: 70_000, bold: true)) == nil)
    }

    @Test func aSixteenColorThemeIsCompletedToXterm256() {
        let colors = ShellXLinkGridConverter.linkPalette(of: .monokai).colors
        #expect(colors.count == 256 && colors[16] == "#000000" && colors[17] == "#00005f" && colors[231] == "#ffffff"
            && colors[232] == "#080808" && colors[255] == "#eeeeee")
    }

    @Test func aSnapshotCarriesScreenHistoryCursorAndPalette() throws {
        let frame = try MobileTerminalRenderGridFrame(
            surfaceID: "s", stateSeq: 1, columns: 10, rows: 3,
            cursor: .init(row: 2, column: 1, visible: true, style: .bar, blinking: true),
            styles: [.default, .init(id: 1, foreground: "#020202", foregroundSource: .palette, foregroundPaletteIndex: 2)],
            rowSpans: [span(0, "hello", width: 5, style: 1), span(0, "$ ", width: 2, row: 2)],
            terminalTheme: theme, scrollbackRows: 2,
            scrollbackSpans: [span(0, "old 1", width: 5, row: 0), span(0, "old 2", width: 5, row: 1)], anchor: .screen
        )
        let link = converter.snapshot(frame)
        #expect(link.head == TerminalFrameHead(
            kind: .snapshot, cols: 10, rows: 3, alt: false,
            cursor: TerminalCursor(x: 1, y: 2, shape: .bar, visible: true, blink: true),
            palette: converter.palette, history: 2
        ))
        #expect(link.styles == [TerminalStyle(id: 1, fg: 2)])
        var screen = TerminalScreen()
        screen.apply(link)
        #expect(screen.screenText() == ["hello", "", "$"] && screen.historyText() == ["old 1", "old 2"])
        _ = try TerminalFrameSplitter.parts(of: link, revision: 1, terminalId: "t-1")
    }

    @Test func aBurstDeltaCarriesItsScrollChangedRowsAndHistory() throws {
        let base = try MobileTerminalRenderGridFrame(
            surfaceID: "s", stateSeq: 1, columns: 10, rows: 2, cursor: .init(row: 1, column: 0),
            rowSpans: [span(0, "r1", width: 2, row: 0), span(0, "r2", width: 2, row: 1)],
            terminalTheme: theme, anchor: .screen
        )
        let burst = try MobileTerminalRenderGridFrame(
            surfaceID: "s", stateSeq: 2, columns: 10, rows: 2, cursor: .init(row: 1, column: 0),
            full: false, clearedRows: [0, 1], rowSpans: [span(0, "r6", width: 2, row: 0)],
            scrollbackRows: 2,
            scrollbackSpans: [span(0, "r4", width: 2, row: 0), span(0, "r5", width: 2, row: 1)],
            anchor: .screen, scrolledRows: 4
        )
        let link = converter.delta(burst)
        #expect(link.head == TerminalFrameHead(
            kind: .delta, cols: 10, rows: 2, cursor: TerminalCursor(x: 0, y: 1), history: 2, scroll: 4
        ))
        #expect(link.lines.contains(TerminalLine(y: 1)))
        var screen = TerminalScreen()
        screen.apply(converter.snapshot(base))
        screen.apply(link)
        #expect(screen.screenText() == ["r6", ""])
        #expect(screen.historyText() == ["r1", "r2", "r4", "r5"])
    }

    @Test func theAlternateScreenHasNoHistory() throws {
        let frame = try MobileTerminalRenderGridFrame(
            surfaceID: "s", stateSeq: 1, columns: 10, rows: 2, rowSpans: [span(0, "vim", width: 3)],
            activeScreen: .alternate, terminalTheme: theme, scrollbackRows: 3,
            scrollbackSpans: [span(0, "a", width: 1, row: 0)], anchor: .screen
        )
        let link = converter.snapshot(frame)
        #expect(link.head.alt && link.head.history == 0)
        #expect(link.lines.allSatisfy { $0.y >= 0 })
    }

    @Test func realGhosttyCellsSurviveTheConversion() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            try await terminal.launch()
            try await terminal.setGrid(columns: 30, rows: 4)
            try terminal.output("\u{1b}ca中e\u{301}\u{1F1FB}\u{1F1F3}\u{2764}\u{FE0F}z\r\nTiếng Việt\r\n")
            try await terminal.waitForScreen(containing: "Vi")
            let capture = try #require(terminal.capture(history: 0))
            let converter = ShellXLinkGridConverter(theme: try #require(capture.terminalTheme))
            var screen = TerminalScreen()
            screen.apply(converter.snapshot(capture))
            let texts = (0..<30).compactMap { x -> String? in
                if case let .glyph(text, _, _) = screen.cell(x: x, y: 0) { return text } else { return nil }
            }
            #expect(texts.contains("中") && texts.contains("e\u{301}") && texts.contains("\u{1F1FB}\u{1F1F3}"))
            #expect(!texts.contains("\u{1F1FB}") && !texts.contains("\u{1F1F3}"))
            #expect(screen.screenText()[1] == "Tiếng Việt")
        }
    }
}
