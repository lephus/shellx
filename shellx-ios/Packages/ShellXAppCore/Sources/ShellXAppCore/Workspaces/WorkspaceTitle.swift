import Foundation
import ShellXLinkCore

/// A workspace name as the phone sends it in `workspace.rename` (PROTOCOL.md section 10).
public enum WorkspaceTitle {
    /// The most characters the rename field takes. Characters are not bytes: a decomposed "ệ" is 5 UTF-8
    /// bytes and a family emoji 25, so `cleaned(_:)` also cuts to `ShellXLink.maxWorkspaceTitleBytes`.
    public static let maxCharacters = 128

    /// `title` as sent: surrounding spaces and line breaks gone, in composed form (NFC, the shortest for
    /// Vietnamese), at most `maxCharacters` characters, and cut on a character boundary to
    /// `ShellXLink.maxWorkspaceTitleBytes` UTF-8 bytes, so the Mac never refuses it for its size.
    public static func cleaned(_ title: String) -> String {
        var name = String(trimmed(title).precomposedStringWithCanonicalMapping.prefix(maxCharacters))
        while name.utf8.count > ShellXLink.maxWorkspaceTitleBytes {
            name.removeLast()
        }
        // A cut can end on a space.
        return trimmed(name)
    }

    /// Whether `title` can be sent: not empty once cleaned (an empty name would only mean "go back to the
    /// automatic one", which the phone does not offer).
    public static func canSave(_ title: String) -> Bool {
        !cleaned(title).isEmpty
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
