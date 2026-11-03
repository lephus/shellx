public import Foundation

/// Trashes through `FileManager.trashItem`.
public struct ShellXFileManagerTrasher: ShellXTrashing {
    // `FileManager` is not `Sendable`, but its documented thread-safe use is exactly this: calling methods on one instance.
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates a trasher backed by `fileManager`.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Moves `url` to the Trash.
    public func trash(_ url: URL) throws {
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }
}
