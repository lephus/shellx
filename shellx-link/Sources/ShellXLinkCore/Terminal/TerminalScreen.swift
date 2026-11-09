import Foundation

/// One cell of a screen row.
public enum TerminalCell: Equatable, Sendable {
    /// A space in the default style.
    case blank
    case glyph(text: String, width: Int, style: TerminalCellStyle)
    /// The second column of a wide cell.
    case continuation
}

/// A run with its column resolved and its style id replaced by the style (PROTOCOL.md 11.5).
public struct TerminalStyledRun: Equatable, Sendable {
    public var x: Int
    public var text: String
    /// Nil: narrow cells, one per Unicode scalar. 1 or 2: one cell of that many columns holding all of `text`.
    public var width: Int?
    public var style: TerminalCellStyle

    public init(x: Int, text: String, width: Int? = nil, style: TerminalCellStyle = .default) {
        self.x = x
        self.text = text
        self.width = width
        self.style = style
    }
}

/// One row of the screen or the history: runs in order, later runs overwriting earlier ones.
public struct TerminalRow: Equatable, Sendable {
    public var runs: [TerminalStyledRun]

    public init(runs: [TerminalStyledRun] = []) {
        self.runs = runs
    }

    /// Exactly `cols` cells. Cells at or past `cols` are dropped, with a wide cell that does not fit whole; a later run
    /// overwrites an earlier one cell by cell (a wide cell half overwritten leaves a blank, not half a glyph).
    public func cells(cols: Int) -> [TerminalCell] {
        guard cols > 0 else { return [] }
        var cells = [TerminalCell](repeating: .blank, count: cols)
        func put(_ index: Int, _ cell: TerminalCell) {
            switch cells[index] {
            case .continuation where index > 0: cells[index - 1] = .blank
            case let .glyph(_, width, _) where width == 2 && index + 1 < cols && cells[index + 1] == .continuation:
                cells[index + 1] = .blank
            default: break
            }
            cells[index] = cell
        }
        for run in runs where run.x >= 0 {
            if let width = run.width {
                guard run.x + width <= cols else { continue }
                put(run.x, .glyph(text: run.text, width: width, style: run.style))
                if width == 2 { put(run.x + 1, .continuation) }
            } else {
                var x = run.x
                for scalar in run.text.unicodeScalars {
                    if x >= cols { break }
                    put(x, .glyph(text: String(scalar), width: 1, style: run.style))
                    x += 1
                }
            }
        }
        return cells
    }

    /// The cells' text from left to right: a blank cell is a space, the second column of a wide cell is nothing, and
    /// trailing spaces are removed (the row text rule of `spec/vectors/terminal.json`).
    public func text(cols: Int) -> String {
        var out = ""
        for cell in cells(cols: cols) {
            switch cell {
            case .blank: out += " "
            case let .glyph(text, _, _): out += text
            case .continuation: break
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }
}

/// What the phone holds for one view: it applies the frames that `TerminalFrameAssembler` admits (PROTOCOL.md 11.6).
public struct TerminalScreen: Equatable, Sendable {
    public static let defaultMaxHistoryRows = 10_000

    public let maxHistoryRows: Int
    /// 0, 0 and false before the first snapshot.
    public private(set) var cols = 0
    public private(set) var rows = 0
    public private(set) var alt = false
    /// Clamped into the grid.
    public private(set) var cursor: TerminalCursor?
    public private(set) var palette: TerminalPalette?
    /// `rows` rows.
    public private(set) var screenRows: [TerminalRow] = []
    /// Oldest first, at most `maxHistoryRows`.
    public private(set) var historyRows: [TerminalRow] = []

    /// False once any history row was dropped since the last snapshot: history frames could no longer join.
    private var historyIntact = true

    public init(maxHistoryRows: Int = TerminalScreen.defaultMaxHistoryRows) {
        self.maxHistoryRows = max(0, maxHistoryRows)
    }

    public mutating func apply(_ frame: TerminalGridFrame) {
        let head = frame.head
        guard head.cols >= 1, head.rows >= 1 else { return }
        switch head.kind {
        case .snapshot:
            let resolver = StyleTable(frame.styles)
            let byY = Self.rowsByY(frame.lines, resolver)
            cols = head.cols
            rows = head.rows
            alt = head.alt
            palette = head.palette
            screenRows = (0..<rows).map { byY[$0] ?? TerminalRow() }
            historyRows = []
            historyIntact = true
            if !alt, head.history > 0 { setHistory(Self.historyRows(head.history, byY), replacing: true) }
            setCursor(head.cursor)
        case .delta:
            guard head.cols == cols, head.rows == rows, head.alt == alt else { return }
            let resolver = StyleTable(frame.styles)
            let byY = Self.rowsByY(frame.lines, resolver)
            if !alt, head.scroll > 0 {
                let k = min(head.scroll, rows)
                var scrolled = Array(screenRows.prefix(k))
                let allowed = max(0, head.scroll - rows)
                let carried = min(head.history, allowed)
                if carried > 0 {
                    // The newest `carried` of the delta's history rows.
                    let all = Self.historyRows(head.history, byY)
                    scrolled += all.suffix(carried)
                }
                appendHistory(scrolled)
                screenRows.removeFirst(k)
                screenRows += [TerminalRow](repeating: TerminalRow(), count: k)
            }
            for (y, row) in byY where (0..<rows).contains(y) { screenRows[y] = row }
            setCursor(head.cursor)
        case .history:
            guard head.cols == cols, head.rows == rows, !alt, !head.alt, historyIntact, head.history > 0 else { return }
            let byY = Self.rowsByY(frame.lines, StyleTable(frame.styles))
            setHistory(Self.historyRows(head.history, byY), replacing: false)
        case .other:
            return
        }
    }

    /// `y` >= 0 is a screen row; `y` < 0 is a history row counted from the newest (-1).
    public func cell(x: Int, y: Int) -> TerminalCell {
        guard x >= 0, x < cols else { return .blank }
        let row: TerminalRow
        if y >= 0 {
            guard y < screenRows.count else { return .blank }
            row = screenRows[y]
        } else {
            let index = historyRows.count + y
            guard index >= 0, index < historyRows.count else { return .blank }
            row = historyRows[index]
        }
        return row.cells(cols: cols)[x]
    }

    public func screenText() -> [String] { screenRows.map { $0.text(cols: cols) } }

    public func historyText() -> [String] { historyRows.map { $0.text(cols: cols) } }

    // MARK: - Internals

    private mutating func setCursor(_ cursor: TerminalCursor?) {
        guard var cursor else { return }
        cursor.x = min(max(cursor.x, 0), cols - 1)
        cursor.y = min(max(cursor.y, 0), rows - 1)
        self.cursor = cursor
    }

    /// Rows that scrolled off the top, at the newest end.
    private mutating func appendHistory(_ newRows: [TerminalRow]) {
        guard !newRows.isEmpty else { return }
        historyRows += newRows
        trimOldest()
    }

    /// `newRows` oldest first. Replacing: the snapshot's own history. Otherwise they go above the oldest row held.
    private mutating func setHistory(_ newRows: [TerminalRow], replacing: Bool) {
        historyRows = newRows + (replacing ? [] : historyRows)
        trimOldest()
    }

    private mutating func trimOldest() {
        let excess = historyRows.count - maxHistoryRows
        if excess > 0 {
            historyRows.removeFirst(excess)
            historyIntact = false
        }
    }

    /// `count` history rows (oldest first) from the lines at y -count ... -1; a row without lines is blank.
    private static func historyRows(_ count: Int, _ byY: [Int: TerminalRow]) -> [TerminalRow] {
        (0..<count).map { byY[$0 - count] ?? TerminalRow() }
    }

    private struct StyleTable {
        private var styles: [Int: TerminalCellStyle] = [:]
        init(_ list: [TerminalStyle]) {
            for style in list { styles[style.id] = style.cellStyle }
        }
        func resolve(_ id: Int?) -> TerminalCellStyle {
            guard let id, id != 0 else { return .default }
            return styles[id] ?? .default
        }
    }

    /// Lines with the same `y` make one row, in order; a run without `x` follows the previous run of its line.
    private static func rowsByY(_ lines: [TerminalLine], _ table: StyleTable) -> [Int: TerminalRow] {
        var byY: [Int: TerminalRow] = [:]
        for line in lines {
            var row = byY[line.y] ?? TerminalRow()
            var next = 0
            for run in line.runs {
                let x = run.x ?? next
                row.runs.append(TerminalStyledRun(x: x, text: run.text, width: run.width, style: table.resolve(run.style)))
                next = x + (run.width ?? run.text.unicodeScalars.count)
            }
            byY[line.y] = row
        }
        return byY
    }
}
