import CmuxSettings
import Foundation

/// Opens Git Graph diffs in the diff viewer by running the bundled CLI, like the
/// "Open Diff Viewer" command does. Holds the workspace through a closure so the
/// controller that stores this opener never retains it.
@MainActor
final class GitGraphDiffOpener: GitGraphDiffOpening {
    private let workspaceProvider: @MainActor () -> Workspace?

    /// `workspaceProvider` is called on every open, so the opener follows whatever
    /// workspace it should target at that moment (for example the selected one).
    init(workspaceProvider: @escaping @MainActor () -> Workspace?) {
        self.workspaceProvider = workspaceProvider
    }

    /// Targets one workspace, held weakly.
    convenience init(workspace: Workspace) {
        self.init(workspaceProvider: { [weak workspace] in workspace })
    }

    func openCommitFileDiff(repositoryRoot: String, sha: String, path: String, patch: Data) -> Bool {
        guard let target = resolveTarget() else { return false }
        let patchURL: URL
        do {
            patchURL = try Self.writePatch(patch, in: Self.patchDirectory)
        } catch {
            return false
        }
        let arguments = Self.commitFileArguments(
            socketPath: target.socketPath,
            patchPath: patchURL.path,
            repositoryRoot: repositoryRoot,
            workspaceId: target.workspace.id,
            title: Self.title(sha: sha, path: path)
        )
        return Self.launch(patchURL: patchURL) { onExit in
            target.appDelegate.spawnBundledDiffViewerCLI(
                cliURL: target.cliURL,
                socketPath: target.socketPath,
                arguments: arguments,
                workspaceId: target.workspace.id,
                surfaceId: nil,
                onExit: onExit
            )
        }
    }

    func openWorkingTreeDiff(repositoryRoot: String) -> Bool {
        guard let target = resolveTarget() else { return false }
        return target.appDelegate.spawnBundledDiffViewerCLI(
            cliURL: target.cliURL,
            socketPath: target.socketPath,
            arguments: Self.workingTreeArguments(
                socketPath: target.socketPath,
                repositoryRoot: repositoryRoot,
                workspaceId: target.workspace.id
            ),
            workspaceId: target.workspace.id,
            surfaceId: nil
        )
    }

    // MARK: - Resolution

    private struct Target {
        let appDelegate: AppDelegate
        let workspace: Workspace
        let cliURL: URL
        let socketPath: String
    }

    private func resolveTarget() -> Target? {
        guard let appDelegate = AppDelegate.shared,
              let workspace = workspaceProvider(),
              let cliURL = Bundle.main.resourceURL?.appendingPathComponent("bin/shellx"),
              FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            return nil
        }
        let socketPath = TerminalController.shared.activeSocketPath(
            preferredPath: SocketControlSettings.socketPath()
        )
        return Target(appDelegate: appDelegate, workspace: workspace, cliURL: cliURL, socketPath: socketPath)
    }

    // MARK: - Pure helpers

    static func title(sha: String, path: String) -> String {
        "\(sha.prefix(7)) \(path)"
    }

    static func commitFileArguments(
        socketPath: String,
        patchPath: String,
        repositoryRoot: String,
        workspaceId: UUID,
        title: String
    ) -> [String] {
        [
            "--socket", socketPath,
            "diff", patchPath,
            "--cwd", repositoryRoot,
            "--workspace", workspaceId.uuidString,
            "--title", title,
            "--focus", "true",
        ]
    }

    static func workingTreeArguments(
        socketPath: String,
        repositoryRoot: String,
        workspaceId: UUID
    ) -> [String] {
        [
            "--socket", socketPath,
            "diff", "--unstaged",
            "--cwd", repositoryRoot,
            "--workspace", workspaceId.uuidString,
            "--focus", "true",
        ]
    }

    // MARK: - Temporary patch files

    static var patchDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shellx-git-graph", isDirectory: true)
    }

    /// Writes `patch` to `<UUID>.patch` (mode 0600) in `directory` (mode 0700, reset
    /// if it already exists with looser permissions).
    static func writePatch(_ patch: Data, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent("\(UUID().uuidString).patch", isDirectory: false)
        guard fileManager.createFile(
            atPath: url.path,
            contents: patch,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Runs `spawn`, handing it the cleanup to run when the process exits. A failed
    /// spawn deletes the patch at once, because no exit callback will ever run.
    static func launch(
        patchURL: URL,
        spawn: (@escaping @MainActor @Sendable () -> Void) -> Bool
    ) -> Bool {
        let spawned = spawn {
            try? FileManager.default.removeItem(at: patchURL)
        }
        if !spawned {
            try? FileManager.default.removeItem(at: patchURL)
        }
        return spawned
    }
}
