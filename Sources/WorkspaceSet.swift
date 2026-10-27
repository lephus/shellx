import Foundation

/// A named list of workspaces saved together, so one command reopens all of them.
struct CmuxWorkspaceSet: Codable, Sendable, Equatable {
    var name: String
    /// Workspaces in sidebar order; each keeps its folder, title, color and splits.
    var workspaces: [CmuxWorkspaceDefinition]
}
