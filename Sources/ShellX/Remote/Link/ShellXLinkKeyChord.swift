import Foundation
import ShellXLinkCore

/// The Mac's named-key spelling (`TerminalSurface.sendNamedKey`) of a phone's key and modifiers: ctrl, alt and shift
/// in that order, then the key, joined with "+" (`ctrl+c`, `shift+tab`, `page_up`). Nil for a key or modifier the
/// Mac does not know (the unit is skipped).
struct ShellXLinkKeyChord: Equatable {
    let macKeyName: String

    init?(key: TerminalKey, mods: [TerminalModifier]) {
        guard let name = Self.name(of: key) else { return nil }
        var ctrl = false
        var alt = false
        var shift = false
        for modifier in mods {
            switch modifier {
            case .ctrl: ctrl = true
            case .alt: alt = true
            case .shift: shift = true
            case .other: return nil
            }
        }
        var parts: [String] = []
        if ctrl { parts.append("ctrl") }
        if alt { parts.append("alt") }
        if shift { parts.append("shift") }
        parts.append(name)
        macKeyName = parts.joined(separator: "+")
    }

    private static func name(of key: TerminalKey) -> String? {
        switch key {
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
        case .letter(let character): return String(character)
        case .other: return nil
        }
    }
}
