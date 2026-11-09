import CoreGraphics
import CoreText
import Foundation
import ShellXAppCore
import ShellXLinkCore

/// One row, laid out once from its cells and drawn from that until the row changes.
///
/// Every cell is placed by its column, never by the font's advance, so a CJK or emoji fallback font cannot push the
/// cells after it sideways: narrow cells are one `CTLine` per segment whose glyphs are moved to their cells' columns,
/// and wide or combined cells are drawn one by one, centred in their columns.
struct TerminalRowLayout {
    struct Cell: Equatable {
        var column: Int
        var width: Int
        var text: String
    }

    /// Consecutive cells of one resolved style (a blank cell counts as a space in the default style).
    struct Segment: Equatable {
        var columns: Range<Int>
        var style: TerminalResolvedStyle
        /// Cells of width 1 and one scalar, each at its column.
        var narrow: [Cell]
        /// Cells of width 2, or of more than one scalar: each drawn on its own, centred in its `width` columns.
        var clusters: [Cell]
    }

    /// Glyphs of one `CTRun` of a segment's narrow cells, already at their cells' x (y from the baseline, up).
    private struct GlyphRun {
        var font: CTFont
        var glyphs: [CGGlyph]
        var positions: [CGPoint]
    }

    private struct ClusterLine {
        var line: CTLine
        /// Left edge of the line once centred in its columns; `squeeze` < 1 when it is wider than they are.
        var x: CGFloat
        var squeeze: CGFloat
    }

    /// What `draw` needs of a segment, built once.
    private struct Drawing {
        var background: CGColor?
        var foreground: CGColor
        var glyphRuns: [GlyphRun]
        var clusters: [ClusterLine]
    }

    let segments: [Segment]
    private let drawings: [Drawing]

    static func segments(_ cells: [TerminalCell], palette: TerminalPalette) -> [Segment] {
        var segments: [Segment] = []
        var lastStyle: TerminalCellStyle?
        var lastResolved: TerminalResolvedStyle?
        func resolved(_ style: TerminalCellStyle) -> TerminalResolvedStyle {
            if let lastStyle, let lastResolved, lastStyle == style { return lastResolved }
            let value = TerminalColors.resolve(style, palette: palette)
            lastStyle = style
            lastResolved = value
            return value
        }
        for (column, cell) in cells.enumerated() {
            let item: Cell
            let style: TerminalResolvedStyle
            let narrow: Bool
            switch cell {
            case .continuation:
                continue
            case .blank:
                item = Cell(column: column, width: 1, text: " ")
                style = resolved(.default)
                narrow = true
            case let .glyph(text, width, cellStyle):
                item = Cell(column: column, width: max(width, 1), text: text)
                style = resolved(cellStyle)
                narrow = width == 1 && text.unicodeScalars.count == 1
            }
            let end = column + item.width
            if var last = segments.last, last.style == style, last.columns.upperBound == column {
                last.columns = last.columns.lowerBound..<end
                if narrow { last.narrow.append(item) } else { last.clusters.append(item) }
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(
                    columns: column..<end, style: style, narrow: narrow ? [item] : [], clusters: narrow ? [] : [item]))
            }
        }
        return segments
    }

    init(row: TerminalRow, cols: Int, palette: TerminalPalette, font: TerminalFont) {
        let segments = Self.segments(row.cells(cols: cols), palette: palette)
        self.segments = segments
        drawings = segments.map { Self.drawing(of: $0, font: font) }
    }

    /// Draws the row with its top at y = 0 in grid units (the caller scaled and translated the context).
    func draw(in context: CGContext, font: TerminalFont) {
        let cell = font.cell
        for (segment, drawing) in zip(segments, drawings) {
            let left = CGFloat(segment.columns.lowerBound) * cell.width
            let width = CGFloat(segment.columns.count) * cell.width
            if let background = drawing.background {
                context.setFillColor(background)
                context.fill(CGRect(x: left, y: 0, width: width, height: cell.height))
            }
            guard segment.style.drawsText else { continue }
            context.setFillColor(drawing.foreground)
            Self.drawText(drawing, in: context, font: font)
            let thickness = font.lineThickness
            if segment.style.underline {
                context.fill(CGRect(x: left, y: font.baseline + font.underlineOffset - thickness / 2, width: width, height: thickness))
            }
            if segment.style.strike {
                context.fill(CGRect(x: left, y: font.baseline - 0.3 * cell.height, width: width, height: thickness))
            }
            if segment.style.overline {
                context.fill(CGRect(x: left, y: 0, width: width, height: thickness))
            }
        }
    }

    /// The glyph cell covering `column` (the second column of a wide cell gives the wide cell) and its style; nil for a blank.
    func cell(at column: Int) -> (cell: Cell, style: TerminalResolvedStyle)? {
        guard let segment = segments.first(where: { $0.columns.contains(column) }) else { return nil }
        let covers = { (cell: Cell) in cell.column <= column && column < cell.column + cell.width }
        guard let found = segment.narrow.first(where: covers) ?? segment.clusters.first(where: covers),
              found.text != " " else { return nil }
        return (found, segment.style)
    }

    /// Draws the text of the cell at `column` alone in `color` (the text under a block cursor).
    func drawCellText(at column: Int, color: CGColor, in context: CGContext, font: TerminalFont) {
        guard case let (found, style)? = self.cell(at: column), style.drawsText else { return }
        let line = Self.line(found.text, font: font.font(bold: style.bold, italic: style.italic))
        context.setFillColor(color)
        Self.drawLine(Self.centred(line, in: found, font: font), in: context, font: font)
    }

    // MARK: - Building

    private static func drawing(of segment: Segment, font: TerminalFont) -> Drawing {
        let style = segment.style
        let face = font.font(bold: style.bold, italic: style.italic)
        var glyphRuns: [GlyphRun] = []
        var clusters: [ClusterLine] = []
        if style.drawsText {
            glyphRuns = narrowRuns(segment.narrow.filter { $0.text != " " }, face: face, cell: font.cell)
            clusters = segment.clusters.map { centred(line($0.text, font: face), in: $0, font: font) }
        }
        return Drawing(
            background: style.background.map(color), foreground: color(style.foreground),
            glyphRuns: glyphRuns, clusters: clusters)
    }

    /// The narrow cells as one line; each glyph moved to the column of the cell whose scalar it comes from, keeping
    /// its offset from the first glyph of that scalar.
    private static func narrowRuns(_ cells: [Cell], face: CTFont, cell: CGSize) -> [GlyphRun] {
        guard !cells.isEmpty else { return [] }
        var text = ""
        var cellOfUTF16: [Int] = []
        for (index, item) in cells.enumerated() {
            text += item.text
            cellOfUTF16 += Array(repeating: index, count: item.text.utf16.count)
        }
        let line = Self.line(text, font: face)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        var firstX: [Int: CGFloat] = [:]
        var result: [GlyphRun] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? face
            for index in 0..<count {
                let utf16 = min(max(indices[index], 0), cellOfUTF16.count - 1)
                let owner = cellOfUTF16[utf16]
                let first = firstX[owner] ?? positions[index].x
                firstX[owner] = first
                positions[index].x = CGFloat(cells[owner].column) * cell.width + (positions[index].x - first)
            }
            result.append(GlyphRun(font: runFont, glyphs: glyphs, positions: positions))
        }
        return result
    }

    private static func line(_ text: String, font: CTFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTLigatureAttributeName as String): 0,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func centred(_ line: CTLine, in cell: Cell, font: TerminalFont) -> ClusterLine {
        let box = CGFloat(cell.width) * font.cell.width
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let squeeze = width > box && width > 0 ? box / width : 1
        let left = CGFloat(cell.column) * font.cell.width + (box - width * squeeze) / 2
        return ClusterLine(line: line, x: left, squeeze: squeeze)
    }

    private static func color(_ rgb: TerminalRGB) -> CGColor {
        CGColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    // MARK: - Drawing

    /// Core Text draws upward from a baseline: flip around the row's baseline first.
    private static func drawText(_ drawing: Drawing, in context: CGContext, font: TerminalFont) {
        if !drawing.glyphRuns.isEmpty {
            context.saveGState()
            context.translateBy(x: 0, y: font.baseline)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            for run in drawing.glyphRuns {
                run.glyphs.withUnsafeBufferPointer { glyphs in
                    run.positions.withUnsafeBufferPointer { positions in
                        guard let glyphs = glyphs.baseAddress, let positions = positions.baseAddress else { return }
                        CTFontDrawGlyphs(run.font, glyphs, positions, run.glyphs.count, context)
                    }
                }
            }
            context.restoreGState()
        }
        for cluster in drawing.clusters { drawLine(cluster, in: context, font: font) }
    }

    private static func drawLine(_ cluster: ClusterLine, in context: CGContext, font: TerminalFont) {
        context.saveGState()
        context.translateBy(x: cluster.x, y: font.baseline)
        context.scaleBy(x: cluster.squeeze, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(cluster.line, context)
        context.restoreGState()
    }
}
