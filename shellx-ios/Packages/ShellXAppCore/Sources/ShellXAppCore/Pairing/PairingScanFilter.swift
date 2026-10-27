import Foundation

/// Sorts what the QR scanner reads. The camera reports a code in view many times a second and
/// sees every QR code around, so the scanner keeps running until a ShellX code shows up:
/// other codes only raise a hint, and a code seen again in a row is ignored.
public struct PairingScanFilter: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// A `shellx-link:` code (trimmed), for `PairingModel.begin(uri:)` to check in full.
        case pairing(String)
        /// Some other QR code: say so, keep scanning.
        case notShellX
        /// The same code as the last one.
        case ignored
    }

    private var last: String?

    public init() {}

    public mutating func accept(_ payload: String) -> Verdict {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != last else { return .ignored }
        last = text
        return Self.isPairingText(text) ? .pairing(text) : .notShellX
    }

    /// True when `text` (blanks around it aside) starts with the `shellx-link:` scheme. The app
    /// uses it to drop a pasted pairing code from the pasteboard once read.
    public static func isPairingText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("shellx-link:")
    }
}
