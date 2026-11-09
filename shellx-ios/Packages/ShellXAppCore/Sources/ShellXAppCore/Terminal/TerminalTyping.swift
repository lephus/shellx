import Foundation
import ShellXLinkCore

/// What the keyboard composes and what it sends (S2 §3.6). Marked text (an input method's word in progress, Telex or VNI)
/// stays on the phone; only committed text goes out. Ctrl, tapped on the key bar, applies to the next key or letter.
public struct TerminalTyping: Equatable, Sendable {
    public private(set) var markedText: String
    public private(set) var ctrlLatched: Bool

    public init(markedText: String = "", ctrlLatched: Bool = false) {
        self.markedText = markedText
        self.ctrlLatched = ctrlLatched
    }

    public mutating func toggleCtrl() {
        ctrlLatched.toggle()
    }

    /// `UITextInput.insertText`. Committing the input method's word is never a ctrl chord.
    public mutating func insert(_ text: String) -> [TerminalInputUnit] {
        let committing = !markedText.isEmpty            // the input method's word becomes this text
        markedText = ""
        guard !committing, ctrlLatched, let first = text.first else { return Self.plain(text) }
        ctrlLatched = false
        return Self.merged(Self.chord(first) + Self.plain(String(text.dropFirst())))
    }

    /// `UITextInput.setMarkedText`. Ctrl takes the first letter of a new composition; the surface then resets the keyboard.
    public mutating func setMarked(_ text: String) -> [TerminalInputUnit] {
        if markedText.isEmpty, ctrlLatched, let first = text.first {
            ctrlLatched = false
            return Self.chord(first)
        }
        markedText = text
        return []
    }

    /// `UITextInput.unmarkText`: what was composed is committed; committing never takes the ctrl latch.
    public mutating func unmark() -> [TerminalInputUnit] {
        defer { markedText = "" }
        return Self.plain(markedText)
    }

    /// `UIKeyInput.deleteBackward`: edits the marked text and, only when there is none, sends backspace.
    public mutating func deleteBackward() -> [TerminalInputUnit] {
        if !markedText.isEmpty {
            markedText.removeLast()
            return []
        }
        return key(.backspace)
    }

    /// A key bar or hardware key. The word in progress goes first; a latched ctrl joins the key's modifiers.
    public mutating func key(_ key: TerminalKey, mods: [TerminalModifier] = []) -> [TerminalInputUnit] {
        var units = unmark()
        var mods = mods
        if ctrlLatched {
            ctrlLatched = false
            if !mods.contains(.ctrl) { mods.insert(.ctrl, at: 0) }
        }
        units.append(.key(key, mods: mods))
        return units
    }

    // MARK: - Text to units

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x1F || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
    }

    /// Line breaks become `enter`, tabs `tab`; other control characters are dropped; each stretch between keys is one
    /// `text` unit.
    static func plain(_ text: String) -> [TerminalInputUnit] {
        var units: [TerminalInputUnit] = []
        var pending = String.UnicodeScalarView()
        func flush() {
            if !pending.isEmpty {
                units.append(.text(String(pending)))
                pending = String.UnicodeScalarView()
            }
        }
        for character in text {
            if isLineBreak(character) {
                flush()
                units.append(.key(.enter, mods: []))
            } else if character == "\t" {
                flush()
                units.append(.key(.tab, mods: []))
            } else {
                pending.append(contentsOf: character.unicodeScalars.filter { !isControl($0) })
            }
        }
        flush()
        return units
    }

    /// One character typed with ctrl: letters, space, a line break and tab become chords; anything else is typed plain.
    static func chord(_ character: Character) -> [TerminalInputUnit] {
        if let ascii = character.asciiValue, (0x41...0x5A).contains(ascii) || (0x61...0x7A).contains(ascii) {
            return [.key(.letter(Character(Unicode.Scalar(ascii | 0x20))), mods: [.ctrl])]
        }
        if character == " " { return [.key(.space, mods: [.ctrl])] }
        if isLineBreak(character) { return [.key(.enter, mods: [.ctrl])] }
        if character == "\t" { return [.key(.tab, mods: [.ctrl])] }
        return plain(String(character))
    }

    /// Adjacent `text` units joined, so a chord that fell back to plain text does not split a stretch.
    private static func merged(_ units: [TerminalInputUnit]) -> [TerminalInputUnit] {
        var result: [TerminalInputUnit] = []
        for unit in units {
            if case let .text(next) = unit, case let .text(previous)? = result.last {
                result[result.count - 1] = .text(previous + next)
            } else {
                result.append(unit)
            }
        }
        return result
    }
}
