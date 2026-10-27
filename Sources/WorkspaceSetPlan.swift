import Foundation

/// Decides which workspaces a set saves and which of its workspaces to open.
enum WorkspaceSetPlan {
    /// The workspaces a new set holds, in sidebar order: the sidebar
    /// multi-selection when it has two or more workspaces, otherwise all of them.
    static func workspaceIdsToSave(orderedIds: [UUID], selectedIds: Set<UUID>) -> [UUID] {
        guard selectedIds.count >= 2 else { return orderedIds }
        return orderedIds.filter { selectedIds.contains($0) }
    }

    /// Indices of the saved workspaces to open, in saved order. A saved folder
    /// that already has an open workspace is skipped, so reopening a set never
    /// duplicates a project. A saved workspace without a folder always opens.
    static func indicesToOpen(
        savedDirectories: [String?],
        openDirectories: [String],
        homeDirectory: String
    ) -> [Int] {
        let open = Set(openDirectories.map { normalizedDirectory($0, homeDirectory: homeDirectory) })
        return savedDirectories.indices.filter { index in
            guard let saved = savedDirectories[index] else { return true }
            return !open.contains(normalizedDirectory(saved, homeDirectory: homeDirectory))
        }
    }

    /// Expands a leading `~` and drops trailing slashes and `.`/`..` segments.
    static func normalizedDirectory(_ path: String, homeDirectory: String) -> String {
        var expanded = path
        if expanded == "~" {
            expanded = homeDirectory
        } else if expanded.hasPrefix("~/") {
            expanded = homeDirectory + expanded.dropFirst()
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
