import Foundation

/// A workspace name as the phone sends it in `workspace.rename` (PROTOCOL.md section 10).
public enum WorkspaceTitle {
    /// The most characters the rename field takes.
    public static let maxCharacters = 128

    /// `title` as sent: surrounding spaces and line breaks gone.
    public static func cleaned(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `title` can be sent: not empty once cleaned (an empty name would only mean "go back to the
    /// automatic one", which the phone does not offer).
    public static func canSave(_ title: String) -> Bool {
        !cleaned(title).isEmpty
    }
}
