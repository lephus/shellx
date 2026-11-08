import CMUXMobileCore
import Foundation
import ShellXLinkCore

/// Turns cmux render-grid captures of one terminal into ShellX Link grid frames (PROTOCOL.md 11.5).
struct ShellXLinkGridConverter {
    /// The Link palette of the capture's effective theme: lowercase colors, exactly 256 indexed colors.
    let palette: TerminalPalette

    init(theme: TerminalTheme) {
        palette = Self.linkPalette(of: theme)
    }

    // MARK: - Frames

    /// A snapshot of a full capture: the screen and, on the main screen, its history rows.
    func snapshot(_ frame: MobileTerminalRenderGridFrame) -> TerminalGridFrame {
        let alternate = frame.activeScreen == .alternate
        let history = alternate ? 0 : frame.scrollbackRows
        let linkStyles = styleTable(frame.styles)
        var lines = historyLines(frame, styles: linkStyles)
        let spansByRow = Dictionary(grouping: frame.rowSpans, by: \.row)
        for row in spansByRow.keys.sorted() {
            let runs = self.runs(of: spansByRow[row] ?? [], styles: linkStyles)
            if !runs.isEmpty { lines.append(TerminalLine(y: row, runs: runs)) }
        }
        let head = TerminalFrameHead(
            kind: .snapshot, cols: frame.columns, rows: frame.rows, alt: alternate,
            cursor: Self.cursor(of: frame), palette: palette, history: history
        )
        return TerminalGridFrame(head: head, styles: usedStyles(lines, in: linkStyles), lines: lines)
    }

    /// A delta of a row-delta capture (`frame.full == false`).
    func delta(_ frame: MobileTerminalRenderGridFrame) -> TerminalGridFrame {
        let alternate = frame.activeScreen == .alternate
        let linkStyles = styleTable(frame.styles)
        var lines = historyLines(frame, styles: linkStyles)
        let spansByRow = Dictionary(grouping: frame.rowSpans, by: \.row)
        for row in frame.clearedRows {
            lines.append(TerminalLine(y: row, runs: runs(of: spansByRow[row] ?? [], styles: linkStyles)))
        }
        let head = TerminalFrameHead(
            kind: .delta, cols: frame.columns, rows: frame.rows, alt: alternate,
            cursor: Self.cursor(of: frame), history: alternate ? 0 : frame.scrollbackRows,
            scroll: alternate ? 0 : frame.scrolledRows
        )
        return TerminalGridFrame(head: head, styles: usedStyles(lines, in: linkStyles), lines: lines)
    }

    private func historyLines(_ frame: MobileTerminalRenderGridFrame, styles: [Int: TerminalStyle]) -> [TerminalLine] {
        guard frame.activeScreen != .alternate, frame.scrollbackRows > 0 else { return [] }
        let spansByRow = Dictionary(grouping: frame.scrollbackSpans, by: \.row)
        var lines: [TerminalLine] = []
        for row in spansByRow.keys.sorted() where (0..<frame.scrollbackRows).contains(row) {
            let runs = self.runs(of: spansByRow[row] ?? [], styles: styles)
            if !runs.isEmpty { lines.append(TerminalLine(y: row - frame.scrollbackRows, runs: runs)) }
        }
        return lines
    }

    private func styleTable(_ styles: [MobileTerminalRenderGridFrame.Style]) -> [Int: TerminalStyle] {
        var table: [Int: TerminalStyle] = [:]
        for source in styles {
            if let converted = style(source) { table[converted.id] = converted }
        }
        return table
    }

    private func usedStyles(_ lines: [TerminalLine], in table: [Int: TerminalStyle]) -> [TerminalStyle] {
        var ids = Set<Int>()
        for line in lines {
            for run in line.runs {
                if let id = run.style, id != 0 { ids.insert(id) }
            }
        }
        return ids.sorted().compactMap { table[$0] }
    }

    private static func cursor(of frame: MobileTerminalRenderGridFrame) -> TerminalCursor {
        guard let cursor = frame.cursor else { return TerminalCursor(x: 0, y: 0, visible: false) }
        let shape: TerminalCursorShape
        switch cursor.style {
        case .block: shape = .block
        case .bar: shape = .bar
        case .underline: shape = .underline
        case .blockHollow: shape = .blockHollow
        }
        return TerminalCursor(x: cursor.column, y: cursor.row, shape: shape, visible: cursor.visible, blink: cursor.blinking)
    }

    // MARK: - Runs

    /// The runs of one row's spans; `styles` holds the frame's Link styles by id (ids missing draw in the default style).
    func runs(of spans: [MobileTerminalRenderGridFrame.RowSpan], styles: [Int: TerminalStyle]) -> [TerminalRun] {
        var runs: [TerminalRun] = []
        var expected = 0
        for span in spans.sorted(by: { $0.column < $1.column }) {
            let scalars = span.text.unicodeScalars.count
            let width = span.cellWidth ?? scalars
            guard scalars > 0, width > 0 else { continue }
            let x: Int? = span.column == expected ? nil : span.column
            let styleID: Int? = styles[span.styleID] != nil ? span.styleID : nil
            if scalars == width && !(width == 2 && span.text.count == 1) {
                runs.append(TerminalRun(x: x, text: span.text, style: styleID))
                expected = span.column + scalars
            } else {
                let cells = min(width, 2)
                runs.append(TerminalRun(
                    x: x, text: Self.cut(span.text, toBytes: ShellXLink.terminalMaxCellTextBytes), style: styleID, width: cells
                ))
                expected = span.column + cells
            }
        }
        return runs
    }

    /// `text` cut to at most `limit` UTF-8 bytes on a scalar boundary.
    private static func cut(_ text: String, toBytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var result = String.UnicodeScalarView()
        var bytes = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            if bytes + size > limit { break }
            result.append(scalar)
            bytes += size
        }
        return String(result)
    }

    // MARK: - Styles

    /// The Link style of a capture style; nil when it draws as the default style or its id is outside 1...65_535.
    func style(_ style: MobileTerminalRenderGridFrame.Style) -> TerminalStyle? {
        guard (1...65_535).contains(style.id) else { return nil }
        var fg: Int?
        var fgRgb: String?
        let resolvedForeground = Self.linkColor(style.foreground)
        switch style.foregroundSource {
        case .palette:
            if let index = style.foregroundPaletteIndex, (0...255).contains(index) {
                if let resolved = resolvedForeground, resolved != palette.colors[index] {
                    fgRgb = resolved
                } else {
                    fg = index
                }
            } else {
                fgRgb = resolvedForeground
            }
        case .rgb:
            fgRgb = resolvedForeground
        case .defaultColor:
            if style.bold, let resolved = resolvedForeground, resolved != palette.fg { fgRgb = resolved }
        case nil:
            if let resolved = resolvedForeground, resolved != palette.fg { fgRgb = resolved }
        }
        var bg: Int?
        var bgRgb: String?
        let resolvedBackground = Self.linkColor(style.background)
        switch style.backgroundSource {
        case .palette:
            if let index = style.backgroundPaletteIndex, (0...255).contains(index) {
                bg = index
            } else {
                bgRgb = resolvedBackground
            }
        case .rgb:
            bgRgb = resolvedBackground
        case .defaultColor:
            break
        case nil:
            if let resolved = resolvedBackground, resolved != palette.bg { bgRgb = resolved }
        }
        var attrs: [TerminalAttribute] = []
        if style.bold { attrs.append(.bold) }
        if style.faint { attrs.append(.faint) }
        if style.italic { attrs.append(.italic) }
        if style.underline { attrs.append(.underline) }
        if style.blink { attrs.append(.blink) }
        if style.inverse { attrs.append(.inverse) }
        if style.invisible { attrs.append(.invisible) }
        if style.strikethrough { attrs.append(.strike) }
        if style.overline { attrs.append(.overline) }
        if fg == nil, fgRgb == nil, bg == nil, bgRgb == nil, attrs.isEmpty { return nil }
        return TerminalStyle(id: style.id, fg: fg, fgRgb: fgRgb, bg: bg, bgRgb: bgRgb, attrs: attrs)
    }

    // MARK: - Palette

    static func linkPalette(of theme: TerminalTheme) -> TerminalPalette {
        let theme = theme.validatedOrDefault()
        let colors: [String]
        if theme.palette.count == TerminalTheme.extendedPaletteCount {
            colors = theme.palette.map(canonical)
        } else {
            colors = theme.palette.map(canonical) + xtermExtension
        }
        return TerminalPalette(
            fg: canonical(theme.foreground), bg: canonical(theme.background),
            cursor: linkColor(theme.cursor), colors: colors
        )
    }

    /// `#rrggbb` lowercase, or nil when `raw` is not `#` plus 6 hex digits.
    static func linkColor(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("#"), raw.utf8.count == 7,
              TerminalTheme.rgbComponents(raw) != nil else { return nil }
        return raw.lowercased()
    }

    /// `rrggbb` or `#rrggbb` as `#rrggbb` lowercase (the theme was validated, so it parses).
    private static func canonical(_ raw: String) -> String {
        guard let rgb = TerminalTheme.rgbComponents(raw) else { return "#000000" }
        return String(format: "#%02x%02x%02x", rgb.red, rgb.green, rgb.blue)
    }

    /// xterm's colors 16...255: the 6x6x6 cube, then 24 grays.
    private static let xtermExtension: [String] = {
        var colors: [String] = []
        for index in 16...231 {
            let n = index - 16
            func level(_ c: Int) -> Int { c == 0 ? 0 : 55 + 40 * c }
            colors.append(String(format: "#%02x%02x%02x", level(n / 36), level((n / 6) % 6), level(n % 6)))
        }
        for index in 232...255 {
            let gray = 8 + 10 * (index - 232)
            colors.append(String(format: "#%02x%02x%02x", gray, gray, gray))
        }
        return colors
    }()
}
