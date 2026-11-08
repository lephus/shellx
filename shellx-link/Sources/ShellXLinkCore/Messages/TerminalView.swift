import Foundation

/// How the host answered `terminal.view.open` (PROTOCOL.md 11.1).
public enum TerminalViewOpenOutcome: LinkWireEnum {
    case ok, notFound, refused, busy, failed
    case other(String)

    public init(wire: String) {
        switch wire {
        case "ok": self = .ok
        case "not_found": self = .notFound
        case "refused": self = .refused
        case "busy": self = .busy
        case "failed": self = .failed
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .ok: return "ok"
        case .notFound: return "not_found"
        case .refused: return "refused"
        case .busy: return "busy"
        case .failed: return "failed"
        case let .other(raw): return raw
        }
    }
}

/// Why a `terminal.view.ended` was sent (PROTOCOL.md 11.1).
public enum TerminalViewEndReason: LinkWireEnum {
    case gone, refused, failed, notOpen
    case other(String)

    public init(wire: String) {
        switch wire {
        case "gone": self = .gone
        case "refused": self = .refused
        case "failed": self = .failed
        case "not_open": self = .notOpen
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .gone: return "gone"
        case .refused: return "refused"
        case .failed: return "failed"
        case .notOpen: return "not_open"
        case let .other(raw): return raw
        }
    }
}

/// A key a phone can press in a terminal view (PROTOCOL.md 11.2).
public enum TerminalKey: LinkWireEnum {
    case enter, tab, backspace, escape, delete, space, up, down, left, right, home, end, pageUp, pageDown
    /// One of "a" to "z" (lowercase ASCII only).
    case letter(Character)
    case other(String)

    /// The 40 names of PROTOCOL.md 11.2 in that order: the 14 named keys, then `.letter("a")` to `.letter("z")`.
    public static let allKnown: [TerminalKey] =
        [.enter, .tab, .backspace, .escape, .delete, .space, .up, .down, .left, .right, .home, .end, .pageUp, .pageDown]
        + (UInt8(ascii: "a")...UInt8(ascii: "z")).map { .letter(Character(UnicodeScalar($0))) }

    public init(wire: String) {
        switch wire {
        case "enter": self = .enter
        case "tab": self = .tab
        case "backspace": self = .backspace
        case "escape": self = .escape
        case "delete": self = .delete
        case "space": self = .space
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        case "home": self = .home
        case "end": self = .end
        case "page_up": self = .pageUp
        case "page_down": self = .pageDown
        default:
            let scalars = Array(wire.unicodeScalars)
            if scalars.count == 1, let c = scalars.first, c.value >= 0x61, c.value <= 0x7A, wire.utf8.count == 1 {
                self = .letter(Character(c))
            } else {
                self = .other(wire)
            }
        }
    }

    public var wire: String {
        switch self {
        case .enter: return "enter"
        case .tab: return "tab"
        case .backspace: return "backspace"
        case .escape: return "escape"
        case .delete: return "delete"
        case .space: return "space"
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .home: return "home"
        case .end: return "end"
        case .pageUp: return "page_up"
        case .pageDown: return "page_down"
        case let .letter(c): return String(c)
        case let .other(raw): return raw
        }
    }
}

/// A modifier of a `key` unit. There is no `cmd`, `super` or `meta`.
public enum TerminalModifier: LinkWireEnum {
    case ctrl, alt, shift
    case other(String)

    public init(wire: String) {
        switch wire {
        case "ctrl": self = .ctrl
        case "alt": self = .alt
        case "shift": self = .shift
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .ctrl: return "ctrl"
        case .alt: return "alt"
        case .shift: return "shift"
        case let .other(raw): return raw
        }
    }
}

/// One unit of a `terminal.view.input` (PROTOCOL.md 11.2). Its `k` is an open enum: an unknown one decodes to `.other`
/// and its other fields are dropped.
public enum TerminalInputUnit: Codable, Equatable, Sendable {
    /// `{"k":"text","text":...}`
    case text(String)
    /// `{"k":"key","key":...,"mods":[...]}`; `mods` is omitted when empty.
    case key(TerminalKey, mods: [TerminalModifier])
    /// `{"k":"paste","text":...}`
    case paste(String)
    /// `{"k":"scroll","lines":...}`
    case scroll(lines: Int)
    /// A unit of a later version: encodes `{"k":kind}`.
    case other(kind: String)

    private enum CodingKeys: String, CodingKey { case k, text, key, mods, lines }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .k)
        switch kind {
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "key":
            let key = TerminalKey(wire: try c.decode(String.self, forKey: .key))
            let mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []
            self = .key(key, mods: mods.map(TerminalModifier.init(wire:)))
        case "paste": self = .paste(try c.decode(String.self, forKey: .text))
        case "scroll": self = .scroll(lines: try c.decode(Int.self, forKey: .lines))
        default: self = .other(kind: kind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try c.encode("text", forKey: .k)
            try c.encode(text, forKey: .text)
        case let .key(key, mods):
            try c.encode("key", forKey: .k)
            try c.encode(key.wire, forKey: .key)
            if !mods.isEmpty { try c.encode(mods.map(\.wire), forKey: .mods) }
        case let .paste(text):
            try c.encode("paste", forKey: .k)
            try c.encode(text, forKey: .text)
        case let .scroll(lines):
            try c.encode("scroll", forKey: .k)
            try c.encode(lines, forKey: .lines)
        case let .other(kind):
            try c.encode(kind, forKey: .k)
        }
    }
}
