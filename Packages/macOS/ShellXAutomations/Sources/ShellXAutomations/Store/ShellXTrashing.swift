public import Foundation

/// Moves a file or folder to the Trash instead of deleting it.
public protocol ShellXTrashing: Sendable {
    /// Moves `url` to the Trash.
    func trash(_ url: URL) throws
}
