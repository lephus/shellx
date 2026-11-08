import CoreText
import ShellXAppCore
import ShellXLinkCore
import UIKit

/// Draws the visible rows of `model.screen` (it keeps no copy of the screen), the cursor and the marked text.
///
/// It covers the visible part of `TerminalSurfaceView`'s content (`origin` is the content point at its top left), so
/// only about a screenful of rows is laid out and drawn, whatever the history holds. Each row's `TerminalRowLayout` is
/// kept until that row changes, so an echo lays out one row again.
final class TerminalCanvasView: UIView {
    /// Rows kept laid out beyond the visible ones, above and below.
    private static let cacheMargin = 40

    private let model: TerminalViewModel
    private let font: TerminalFont

    var scale: CGFloat = 1 {
        didSet { if scale != oldValue { setNeedsDisplay() } }
    }
    var showsCursor = true {
        didSet { if showsCursor != oldValue { setNeedsDisplay() } }
    }
    /// The content point (of the surface) drawn at this view's top left.
    var origin: CGPoint = .zero {
        didSet { if origin != oldValue { setNeedsDisplay() } }
    }

    private var cache: [Int: (row: TerminalRow, layout: TerminalRowLayout)] = [:]
    private var cacheCols = 0
    private var cachePalette: TerminalPalette?

    init(model: TerminalViewModel, font: TerminalFont) {
        self.model = model
        self.font = font
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        let screen = model.screen
        guard let palette = screen.palette, screen.cols > 0, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(Self.color(TerminalColors.background(palette)))
        context.fill(bounds)
        if palette != cachePalette || screen.cols != cacheCols {
            cache.removeAll()
            cachePalette = palette
            cacheCols = screen.cols
        }

        let history = screen.alt ? 0 : screen.historyRows.count
        let shown = history + screen.rows
        let rowHeight = font.cell.height * scale
        guard rowHeight > 0, shown > 0 else { return }
        let padding = TerminalGeometry.padding
        let first = max(0, Int(((origin.y - padding) / rowHeight).rounded(.down)))
        let last = min(shown - 1, Int(((origin.y + bounds.height - padding) / rowHeight).rounded(.up)))

        context.saveGState()
        context.translateBy(x: padding - origin.x, y: padding - origin.y)
        context.scaleBy(x: scale, y: scale)
        if first <= last {
            for index in first...last {
                guard let row = Self.row(index, of: screen, history: history) else { continue }
                let layout = layout(index, row: row, screen: screen, palette: palette)
                context.saveGState()
                context.translateBy(x: 0, y: CGFloat(index) * font.cell.height)
                layout.draw(in: context, font: font)
                context.restoreGState()
            }
        }
        drawCursor(in: context, screen: screen, palette: palette, history: history)
        drawMarkedText(in: context, screen: screen, palette: palette, history: history)
        context.restoreGState()
        cache = cache.filter { $0.key >= first - Self.cacheMargin && $0.key <= last + Self.cacheMargin }
    }

    // MARK: - Rows

    private static func row(_ index: Int, of screen: TerminalScreen, history: Int) -> TerminalRow? {
        if index < history { return screen.historyRows[index] }
        let y = index - history
        guard y < screen.rows else { return nil }
        return screen.screenRows.indices.contains(y) ? screen.screenRows[y] : TerminalRow()
    }

    private func layout(_ index: Int, row: TerminalRow, screen: TerminalScreen, palette: TerminalPalette) -> TerminalRowLayout {
        if let entry = cache[index], entry.row == row { return entry.layout }
        let layout = TerminalRowLayout(row: row, cols: screen.cols, palette: palette, font: font)
        cache[index] = (row, layout)
        return layout
    }

    // MARK: - Cursor and marked text

    /// The cursor's box in grid units (two columns over a wide cell) and the row layout under it.
    private func cursorBox(screen: TerminalScreen, palette: TerminalPalette, history: Int)
        -> (box: CGRect, column: Int, layout: TerminalRowLayout)?
    {
        guard let cursor = screen.cursor, cursor.y >= 0, cursor.y < screen.rows, cursor.x >= 0, cursor.x < screen.cols
        else { return nil }
        let index = history + cursor.y
        let row = Self.row(index, of: screen, history: history) ?? TerminalRow()
        let layout = layout(index, row: row, screen: screen, palette: palette)
        let found = layout.cell(at: cursor.x)?.cell
        let column = found?.column ?? cursor.x
        let width = found?.width ?? 1
        let box = CGRect(
            x: CGFloat(column) * font.cell.width, y: CGFloat(index) * font.cell.height,
            width: CGFloat(width) * font.cell.width, height: font.cell.height)
        return (box, column, layout)
    }

    private func drawCursor(in context: CGContext, screen: TerminalScreen, palette: TerminalPalette, history: Int) {
        guard showsCursor, screen.cursor?.visible == true, model.typing.markedText.isEmpty,
              let cursor = screen.cursor, case let (box, column, layout)? = cursorBox(screen: screen, palette: palette, history: history)
        else { return }
        let color = Self.color(TerminalColors.cursor(palette))
        context.setFillColor(color)
        context.setStrokeColor(color)
        switch cursor.shape {
        case .bar:
            context.fill(CGRect(x: box.minX, y: box.minY, width: 2, height: box.height))
        case .underline:
            context.fill(CGRect(x: box.minX, y: box.maxY - 2, width: box.width, height: 2))
        case .blockHollow:
            context.setLineWidth(1)
            context.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case .block, .other:
            context.fill(box)
            context.saveGState()
            context.translateBy(x: 0, y: box.minY)
            layout.drawCellText(at: column, color: Self.color(TerminalColors.background(palette)), in: context, font: font)
            context.restoreGState()
        }
    }

    /// The text the keyboard is composing, at the cursor's cell: palette foreground on palette background, underlined.
    private func drawMarkedText(in context: CGContext, screen: TerminalScreen, palette: TerminalPalette, history: Int) {
        let marked = model.typing.markedText
        guard !marked.isEmpty, case let (box, _, _)? = cursorBox(screen: screen, palette: palette, history: history) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font.font(bold: false, italic: false),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: marked, attributes: attributes))
        let width = max(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), font.cell.width)
        let area = CGRect(x: box.minX, y: box.minY, width: width, height: font.cell.height)
        context.setFillColor(Self.color(TerminalColors.background(palette)))
        context.fill(area)
        let foreground = Self.color(TerminalColors.foreground(palette))
        context.setFillColor(foreground)
        context.saveGState()
        context.translateBy(x: area.minX, y: area.minY + font.baseline)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        // At the cell's bottom, below the font's underline position, so the dots under Vietnamese vowels (ạ, ệ) stay clear.
        context.fill(CGRect(x: area.minX, y: area.maxY - 1, width: width, height: 1))
    }

    /// The marked text's first cell in this view's coordinates (the keyboard's caret and candidate bar, Task 9).
    func cursorRect() -> CGRect {
        let screen = model.screen
        guard let palette = screen.palette else { return CGRect(x: TerminalGeometry.padding, y: TerminalGeometry.padding, width: 0, height: font.cell.height) }
        let history = screen.alt ? 0 : screen.historyRows.count
        guard case let (box, _, _)? = cursorBox(screen: screen, palette: palette, history: history) else { return .zero }
        let padding = TerminalGeometry.padding
        return CGRect(
            x: padding - origin.x + box.minX * scale, y: padding - origin.y + box.minY * scale,
            width: box.width * scale, height: box.height * scale)
    }

    static func color(_ rgb: TerminalRGB) -> CGColor {
        CGColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}
