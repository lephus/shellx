import ShellXAppCore
import UIKit

/// Reads a pasted pairing code.
enum PairingPaste {
    /// The pasteboard's text, read once. A pairing code is then cleared from the pasteboard: it
    /// carries a one-time secret that should not stay around for other apps.
    @MainActor
    static func take(from pasteboard: UIPasteboard) -> String {
        let text = pasteboard.string ?? ""
        if PairingScanFilter.isPairingText(text) { pasteboard.items = [] }
        return text
    }
}
