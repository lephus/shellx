import Foundation

/// What a Git Graph follows: a local directory, a terminal on another host (whose
/// repository this Mac cannot read), or nothing.
enum GitGraphTarget: Equatable {
    case directory(String)
    case remote
    case none
}

/// Picks the Git Graph's target the way `ContentView.focusedDirectory` picks a
/// directory: a non-empty local focused-panel directory wins; a remote focused panel
/// or a workspace with remote directory provenance is `.remote`; otherwise the
/// workspace's presented directory, or `.none`.
enum GitGraphTargetPolicy {
    static func target(
        focusedPanelDirectory: String?,
        focusedPanelIsRemote: Bool,
        usesRemoteDirectoryProvenance: Bool,
        presentedDirectory: String?
    ) -> GitGraphTarget {
        if !focusedPanelIsRemote, let directory = nonEmpty(focusedPanelDirectory) {
            return .directory(directory)
        }
        if focusedPanelIsRemote || usesRemoteDirectoryProvenance {
            return .remote
        }
        return nonEmpty(presentedDirectory).map(GitGraphTarget.directory) ?? .none
    }

    /// The target for `workspace`'s focused panel. A cloud-projected panel counts as
    /// remote: its directory belongs to the cloud machine, not this Mac.
    @MainActor
    static func target(for workspace: Workspace) -> GitGraphTarget {
        let focusedPanelId = workspace.focusedPanelId
        return target(
            focusedPanelDirectory: focusedPanelId.flatMap { workspace.reportedPanelDirectory(panelId: $0) },
            focusedPanelIsRemote: focusedPanelId.map {
                workspace.isRemoteTerminalSurface($0) || workspace.cloudDirectoryProvenanceRequired(panelId: $0)
            } ?? false,
            usesRemoteDirectoryProvenance: workspace.usesRemoteDirectoryProvenance,
            presentedDirectory: workspace.presentedCurrentDirectory
        )
    }

    private static func nonEmpty(_ directory: String?) -> String? {
        guard let trimmed = directory?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
