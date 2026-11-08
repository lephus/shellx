import Foundation
import ShellXLinkCore

/// Turns input units into `terminal.view.input` messages within plan 2A's limits (PROTOCOL.md 11.2).
public enum TerminalInputBatcher {
    /// The largest paste the phone sends: 16 messages of 16 384 bytes. The host keeps at most 64 queued input messages
    /// (plan 2A), so a longer paste could silently lose its tail; R12 refuses it instead and the pane shows
    /// `terminal.paste.tooLarge`.
    public static let maxPasteBytes = 262_144

    /// `units` as `terminal.view.input` messages, in order. Every message passes `TerminalInputCheck.check`: 1 to 64 units,
    /// typed text at most 4 096 UTF-8 bytes in all, pasted text at most 16 384; a longer `text` or `paste` unit is cut into
    /// pieces at Character boundaries (a Character longer than the limit at scalar boundaries).
    public static func messages(_ units: [TerminalInputUnit]) -> [[TerminalInputUnit]] {
        var messages: [[TerminalInputUnit]] = []
        var current: [TerminalInputUnit] = []
        var typedBytes = 0
        var pastedBytes = 0

        func add(_ unit: TerminalInputUnit, typed: Int, pasted: Int) {
            if current.count == ShellXLink.terminalMaxInputUnits
                || typedBytes + typed > ShellXLink.terminalMaxTextBytes
                || pastedBytes + pasted > ShellXLink.terminalMaxPasteBytes {
                messages.append(current)
                current = []
                typedBytes = 0
                pastedBytes = 0
            }
            current.append(unit)
            typedBytes += typed
            pastedBytes += pasted
        }

        for unit in units {
            switch unit {
            case let .text(text):
                for piece in pieces(text, maxBytes: ShellXLink.terminalMaxTextBytes) {
                    add(.text(piece), typed: piece.utf8.count, pasted: 0)
                }
            case let .paste(text):
                for piece in pieces(text, maxBytes: ShellXLink.terminalMaxPasteBytes) {
                    add(.paste(piece), typed: 0, pasted: piece.utf8.count)
                }
            default:
                add(unit, typed: 0, pasted: 0)
            }
        }
        if !current.isEmpty { messages.append(current) }
        return messages
    }

    /// Pasted text as one `paste` unit, with every control character but tab, line feed and carriage return dropped; [] when
    /// nothing is left.
    public static func pasteUnits(_ text: String) -> [TerminalInputUnit] {
        let cleaned = cleanPaste(text)
        return cleaned.isEmpty ? [] : [.paste(cleaned)]
    }

    /// True when the cleaned paste (as `pasteUnits` would send it) is at most `maxPasteBytes` UTF-8 bytes.
    public static func pasteFits(_ text: String) -> Bool {
        cleanPaste(text).utf8.count <= maxPasteBytes
    }

    /// A scroll of `lines` (either sign) as units of at most 100 lines each, in the same direction; [] for 0.
    public static func scrollUnits(_ lines: Int) -> [TerminalInputUnit] {
        let step = ShellXLink.terminalMaxScrollLines
        let sign = lines < 0 ? -1 : 1
        var left = lines.magnitude
        var units: [TerminalInputUnit] = []
        while left > 0 {
            let part = Int(min(left, UInt(step)))
            units.append(.scroll(lines: sign * part))
            left -= UInt(part)
        }
        return units
    }

    // MARK: - Helpers

    private static func cleanPaste(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { scalar in
            let v = scalar.value
            let control = v <= 0x1F || v == 0x7F || (0x80...0x9F).contains(v)
            return !control || v == 0x09 || v == 0x0A || v == 0x0D
        })
        return String(scalars)
    }

    /// `text` cut into non-empty pieces of at most `maxBytes` UTF-8 bytes at Character boundaries; a Character longer than
    /// `maxBytes` is cut at scalar boundaries.
    private static func pieces(_ text: String, maxBytes: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.utf8.count > maxBytes else { return [text] }
        var result: [String] = []
        var piece = ""
        var pieceBytes = 0
        func flush() {
            if !piece.isEmpty {
                result.append(piece)
                piece = ""
                pieceBytes = 0
            }
        }
        for character in text {
            let bytes = character.utf8.count
            if bytes > maxBytes {
                flush()
                var scalars = String.UnicodeScalarView()
                var scalarBytes = 0
                for scalar in character.unicodeScalars {
                    let size = String(scalar).utf8.count
                    if scalarBytes + size > maxBytes, !scalars.isEmpty {
                        result.append(String(scalars))
                        scalars = String.UnicodeScalarView()
                        scalarBytes = 0
                    }
                    scalars.append(scalar)
                    scalarBytes += size
                }
                if !scalars.isEmpty { result.append(String(scalars)) }
                continue
            }
            if pieceBytes + bytes > maxBytes { flush() }
            piece.append(character)
            pieceBytes += bytes
        }
        flush()
        return result
    }
}
