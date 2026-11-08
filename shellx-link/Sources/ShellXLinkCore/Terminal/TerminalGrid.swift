import Foundation

/// What a `terminal.view.frame` holds (PROTOCOL.md 11.4).
public enum TerminalFrameKind: LinkWireEnum {
    case snapshot, delta, history
    case other(String)

    public init(wire: String) {
        switch wire {
        case "snapshot": self = .snapshot
        case "delta": self = .delta
        case "history": self = .history
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .snapshot: return "snapshot"
        case .delta: return "delta"
        case .history: return "history"
        case let .other(raw): return raw
        }
    }
}

public enum TerminalCursorShape: LinkWireEnum {
    case block, bar, underline, blockHollow
    case other(String)

    public init(wire: String) {
        switch wire {
        case "block": self = .block
        case "bar": self = .bar
        case "underline": self = .underline
        case "block_hollow": self = .blockHollow
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .block: return "block"
        case .bar: return "bar"
        case .underline: return "underline"
        case .blockHollow: return "block_hollow"
        case let .other(raw): return raw
        }
    }
}

public enum TerminalAttribute: LinkWireEnum {
    case bold, faint, italic, underline, blink, inverse, invisible, strike, overline
    case other(String)

    public init(wire: String) {
        switch wire {
        case "bold": self = .bold
        case "faint": self = .faint
        case "italic": self = .italic
        case "underline": self = .underline
        case "blink": self = .blink
        case "inverse": self = .inverse
        case "invisible": self = .invisible
        case "strike": self = .strike
        case "overline": self = .overline
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .bold: return "bold"
        case .faint: return "faint"
        case .italic: return "italic"
        case .underline: return "underline"
        case .blink: return "blink"
        case .inverse: return "inverse"
        case .invisible: return "invisible"
        case .strike: return "strike"
        case .overline: return "overline"
        case let .other(raw): return raw
        }
    }
}

public struct TerminalCursor: Codable, Equatable, Sendable {
    /// Column, 0 at the left.
    public var x: Int
    /// Screen row, 0 at the top.
    public var y: Int
    public var shape: TerminalCursorShape
    public var visible: Bool
    public var blink: Bool

    public init(x: Int, y: Int, shape: TerminalCursorShape = .block, visible: Bool = true, blink: Bool = false) {
        self.x = x
        self.y = y
        self.shape = shape
        self.visible = visible
        self.blink = blink
    }
}

/// The terminal's colors (PROTOCOL.md 11.5). A color is `#rrggbb`.
public struct TerminalPalette: Codable, Equatable, Sendable {
    public var fg: String
    public var bg: String
    /// Absent means the cursor takes the foreground color.
    public var cursor: String?
    /// Exactly 256 colors: the indexed palette.
    public var colors: [String]

    public init(fg: String, bg: String, cursor: String? = nil, colors: [String]) {
        self.fg = fg
        self.bg = bg
        self.cursor = cursor
        self.colors = colors
    }
}

/// A resolved style: what a cell is drawn with. The default style has default colors and no attribute.
public struct TerminalCellStyle: Equatable, Sendable {
    public var fg: Int?
    public var fgRgb: String?
    public var bg: Int?
    public var bgRgb: String?
    public var attrs: [TerminalAttribute]

    public static let `default` = TerminalCellStyle()

    public init(fg: Int? = nil, fgRgb: String? = nil, bg: Int? = nil, bgRgb: String? = nil, attrs: [TerminalAttribute] = []) {
        self.fg = fg
        self.fgRgb = fgRgb
        self.bg = bg
        self.bgRgb = bgRgb
        self.attrs = attrs
    }
}

/// An entry of a frame's style table (PROTOCOL.md 11.5). Its `id` means something only in its frame.
public struct TerminalStyle: Codable, Equatable, Sendable {
    public var id: Int
    public var fg: Int?
    public var fgRgb: String?
    public var bg: Int?
    public var bgRgb: String?
    public var attrs: [TerminalAttribute]

    public var cellStyle: TerminalCellStyle {
        TerminalCellStyle(fg: fg, fgRgb: fgRgb, bg: bg, bgRgb: bgRgb, attrs: attrs)
    }

    public init(id: Int, fg: Int? = nil, fgRgb: String? = nil, bg: Int? = nil, bgRgb: String? = nil, attrs: [TerminalAttribute] = []) {
        self.id = id
        self.fg = fg
        self.fgRgb = fgRgb
        self.bg = bg
        self.bgRgb = bgRgb
        self.attrs = attrs
    }

    private enum CodingKeys: String, CodingKey { case id, fg, fgRgb, bg, bgRgb, attrs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fg = try c.decodeIfPresent(Int.self, forKey: .fg)
        fgRgb = try c.decodeIfPresent(String.self, forKey: .fgRgb)
        bg = try c.decodeIfPresent(Int.self, forKey: .bg)
        bgRgb = try c.decodeIfPresent(String.self, forKey: .bgRgb)
        attrs = try c.decodeIfPresent([TerminalAttribute].self, forKey: .attrs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(fg, forKey: .fg)
        try c.encodeIfPresent(fgRgb, forKey: .fgRgb)
        try c.encodeIfPresent(bg, forKey: .bg)
        try c.encodeIfPresent(bgRgb, forKey: .bgRgb)
        if !attrs.isEmpty { try c.encode(attrs, forKey: .attrs) }
    }
}

/// A stretch of cells of one style (PROTOCOL.md 11.5). Wire keys `x`, `t`, `s`, `w`.
public struct TerminalRun: Codable, Equatable, Sendable {
    /// The first column; absent means right after the previous run of the line (0 for the first).
    public var x: Int?
    public var text: String
    /// The style id; absent or 0 means the default style.
    public var style: Int?
    /// With a width the run is exactly one cell of that many columns (1 or 2).
    public var width: Int?

    public init(x: Int? = nil, text: String, style: Int? = nil, width: Int? = nil) {
        self.x = x
        self.text = text
        self.style = style
        self.width = width
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case text = "t"
        case style = "s"
        case width = "w"
    }
}

public struct TerminalLine: Codable, Equatable, Sendable {
    /// 0 to rows - 1 for the screen, -1 to -history for history rows (-1 the newest).
    public var y: Int
    public var runs: [TerminalRun]

    public init(y: Int, runs: [TerminalRun] = []) {
        self.y = y
        self.runs = runs
    }

    private enum CodingKeys: String, CodingKey { case y, runs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        y = try c.decode(Int.self, forKey: .y)
        runs = try c.decodeIfPresent([TerminalRun].self, forKey: .runs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(y, forKey: .y)
        if !runs.isEmpty { try c.encode(runs, forKey: .runs) }
    }
}

/// The head of a frame, carried by its part 0 (PROTOCOL.md 11.5).
public struct TerminalFrameHead: Codable, Equatable, Sendable {
    public var kind: TerminalFrameKind
    public var cols: Int
    public var rows: Int
    public var alt: Bool
    public var cursor: TerminalCursor?
    public var palette: TerminalPalette?
    /// History rows the frame carries; omitted from the wire when 0.
    public var history: Int
    /// Rows that left the top of the screen since the frame before (deltas); omitted from the wire when 0.
    public var scroll: Int

    public init(
        kind: TerminalFrameKind, cols: Int, rows: Int, alt: Bool = false, cursor: TerminalCursor? = nil,
        palette: TerminalPalette? = nil, history: Int = 0, scroll: Int = 0
    ) {
        self.kind = kind
        self.cols = cols
        self.rows = rows
        self.alt = alt
        self.cursor = cursor
        self.palette = palette
        self.history = history
        self.scroll = scroll
    }

    private enum CodingKeys: String, CodingKey { case kind, cols, rows, alt, cursor, palette, history, scroll }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(TerminalFrameKind.self, forKey: .kind)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        alt = try c.decode(Bool.self, forKey: .alt)
        cursor = try c.decodeIfPresent(TerminalCursor.self, forKey: .cursor)
        palette = try c.decodeIfPresent(TerminalPalette.self, forKey: .palette)
        history = try c.decodeIfPresent(Int.self, forKey: .history) ?? 0
        scroll = try c.decodeIfPresent(Int.self, forKey: .scroll) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(cols, forKey: .cols)
        try c.encode(rows, forKey: .rows)
        try c.encode(alt, forKey: .alt)
        try c.encodeIfPresent(cursor, forKey: .cursor)
        try c.encodeIfPresent(palette, forKey: .palette)
        if history != 0 { try c.encode(history, forKey: .history) }
        if scroll != 0 { try c.encode(scroll, forKey: .scroll) }
    }
}

/// One message of a frame: `terminal.view.frame` without its `terminal_id` (PROTOCOL.md 11.4).
public struct TerminalFramePart: Equatable, Sendable {
    public var revision: Int
    public var part: Int
    public var parts: Int
    /// Required in part 0, absent in the others.
    public var head: TerminalFrameHead?
    public var styles: [TerminalStyle]
    public var lines: [TerminalLine]

    public init(
        revision: Int, part: Int = 0, parts: Int = 1, head: TerminalFrameHead? = nil,
        styles: [TerminalStyle] = [], lines: [TerminalLine] = []
    ) {
        self.revision = revision
        self.part = part
        self.parts = parts
        self.head = head
        self.styles = styles
        self.lines = lines
    }
}

/// One whole frame (all parts merged): what a host's source yields and what the assembler admits.
public struct TerminalGridFrame: Equatable, Sendable {
    public var head: TerminalFrameHead
    public var styles: [TerminalStyle]
    public var lines: [TerminalLine]

    public init(head: TerminalFrameHead, styles: [TerminalStyle] = [], lines: [TerminalLine] = []) {
        self.head = head
        self.styles = styles
        self.lines = lines
    }
}

extension TerminalFramePart {
    /// The structural rules of PROTOCOL.md 11.4 and 11.5 that the codec enforces on encode and decode. Size limits of
    /// a grid (beyond 1 000) are not checked here: a receiver treats them as a gap (11.7).
    var isValid: Bool {
        guard revision >= 1, (1...ShellXLink.terminalMaxFrameParts).contains(parts), (0..<parts).contains(part) else {
            return false
        }
        if let head {
            guard head.cols >= 1, head.rows >= 1, head.history >= 0, head.scroll >= 0 else { return false }
            if let cursor = head.cursor, cursor.x < 0 || cursor.y < 0 { return false }
            if let palette = head.palette {
                guard Self.isColor(palette.fg), Self.isColor(palette.bg), palette.cursor.map(Self.isColor) ?? true,
                      palette.colors.count == 256, palette.colors.allSatisfy(Self.isColor)
                else { return false }
            }
        }
        for style in styles {
            guard (1...65_535).contains(style.id) else { return false }
            if let fg = style.fg, !(0...255).contains(fg) { return false }
            if let bg = style.bg, !(0...255).contains(bg) { return false }
            if let rgb = style.fgRgb, !Self.isColor(rgb) { return false }
            if let rgb = style.bgRgb, !Self.isColor(rgb) { return false }
            if style.fg != nil && style.fgRgb != nil { return false }
            if style.bg != nil && style.bgRgb != nil { return false }
        }
        for line in lines {
            for run in line.runs {
                if run.text.isEmpty { return false }
                if let w = run.width, !(1...2).contains(w) { return false }
                if let x = run.x, x < 0 { return false }
                if let s = run.style, s < 0 { return false }
            }
        }
        return true
    }

    /// `#` followed by 6 hexadecimal digits, either case.
    static func isColor(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return false }
        return bytes.dropFirst().allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66)
        }
    }
}
