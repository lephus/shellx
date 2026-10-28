import Foundation

/// Decides which workspaces a set saves and which of its workspaces to open.
enum WorkspaceSetPlan {
    /// Whether a new set holds only the sidebar multi-selection: two or more of
    /// the workspaces a set can hold are selected. Selected workspaces outside
    /// `orderedIds`, such as remote ones, do not count.
    static func savesSelection(orderedIds: [UUID], selectedIds: Set<UUID>) -> Bool {
        orderedIds.filter { selectedIds.contains($0) }.count >= 2
    }

    /// The workspaces a new set holds, in sidebar order: the sidebar
    /// multi-selection when it has two or more workspaces, otherwise all of them.
    static func workspaceIdsToSave(orderedIds: [UUID], selectedIds: Set<UUID>) -> [UUID] {
        guard savesSelection(orderedIds: orderedIds, selectedIds: selectedIds) else { return orderedIds }
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
        let openIndices = openWorkspaceIndices(
            savedDirectories: savedDirectories,
            openDirectories: openDirectories,
            homeDirectory: homeDirectory
        )
        return openIndices.indices.filter { openIndices[$0] == nil }
    }

    /// For each saved workspace, the index of the first open directory that
    /// already covers its folder, or nil when the workspace has to be opened.
    /// An open directory covers the same saved folder, or else the deepest saved
    /// folder around it, so a workspace that has `cd`'d into a subfolder still
    /// counts as open. The home folder and its parents only match exactly,
    /// because every project lives under them.
    static func openWorkspaceIndices(
        savedDirectories: [String?],
        openDirectories: [String],
        homeDirectory: String
    ) -> [Int?] {
        let home = normalizedDirectory(homeDirectory, homeDirectory: homeDirectory)
        let saved = savedDirectories.map { $0.map { normalizedDirectory($0, homeDirectory: homeDirectory) } }
        let folders = Set(saved.compactMap { $0 })
        let enclosingFolders = folders.filter { home != $0 && !isPath(home, inside: $0) }

        var openIndexByFolder: [String: Int] = [:]
        for (index, openDirectory) in openDirectories.enumerated() {
            let directory = normalizedDirectory(openDirectory, homeDirectory: homeDirectory)
            let folder = folders.contains(directory)
                ? directory
                : enclosingFolders.filter { isPath(directory, inside: $0) }.max { $0.count < $1.count }
            if let folder, openIndexByFolder[folder] == nil {
                openIndexByFolder[folder] = index
            }
        }
        return saved.map { $0.flatMap { openIndexByFolder[$0] } }
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

    private static func isPath(_ path: String, inside folder: String) -> Bool {
        path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
