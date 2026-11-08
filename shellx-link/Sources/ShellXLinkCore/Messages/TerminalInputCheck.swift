import Foundation

/// A `terminal.view.input` that breaks a rule of PROTOCOL.md 11.2. `reason` is a fixed English phrase and never
/// quotes the units.
public struct TerminalInputError: Error, Equatable, Sendable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

/// The input rules of PROTOCOL.md 11.2, shared by the client (before sending) and the host (before applying).
public enum TerminalInputCheck {
    /// Throws a `TerminalInputError` when `units` break a rule. `.other` units, unknown keys and unknown modifiers pass.
    public static func check(_ units: [TerminalInputUnit]) throws(TerminalInputError) {
        guard (1...ShellXLink.terminalMaxInputUnits).contains(units.count) else {
            throw TerminalInputError(reason: "an input message carries 1 to 64 units")
        }
        var typedBytes = 0
        var pastedBytes = 0
        for unit in units {
            switch unit {
            case let .text(text):
                if text.isEmpty { throw TerminalInputError(reason: "text is empty") }
                if text.unicodeScalars.contains(where: isControl) {
                    throw TerminalInputError(reason: "text holds a control character")
                }
                typedBytes += text.utf8.count
                if typedBytes > ShellXLink.terminalMaxTextBytes {
                    throw TerminalInputError(reason: "typed text is over 4096 bytes")
                }
            case let .paste(text):
                if text.isEmpty { throw TerminalInputError(reason: "pasted text is empty") }
                if text.unicodeScalars.contains(where: { isControl($0) && !pasteAllowed.contains($0.value) }) {
                    throw TerminalInputError(reason: "pasted text holds a control character")
                }
                pastedBytes += text.utf8.count
                if pastedBytes > ShellXLink.terminalMaxPasteBytes {
                    throw TerminalInputError(reason: "pasted text is over 16384 bytes")
                }
            case let .scroll(lines):
                if lines == 0 || abs(lines) > ShellXLink.terminalMaxScrollLines {
                    throw TerminalInputError(reason: "scroll lines must be 1 to 100 either way")
                }
            case let .key(_, mods):
                var seen = Set<String>()
                for mod in mods where !seen.insert(mod.wire).inserted {
                    throw TerminalInputError(reason: "a modifier is repeated")
                }
            case .other:
                break
            }
        }
    }

    private static let pasteAllowed: Set<UInt32> = [0x09, 0x0A, 0x0D]

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x1F || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
    }
}
