import CmuxSettings
import CmuxWorkspaces
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX's runtime names on disk never collide with an installed cmux:
/// state dir, control socket, global config, CLI install path, the bundled CLI
/// and Application Support (plan Task 3, Review Focus 1).
struct ShellXPathsTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func runtimePathsAreShellX() {
        #expect(CmuxStateDirectory.url(homeDirectory: home).path.hasSuffix("/.local/state/shellx"))
        #expect(SocketControlSettings.stableSocketFileName.hasPrefix("shellx"))
        #expect(SocketControlSettings.stableDefaultSocketPath.hasSuffix("/.local/state/shellx/shellx.sock"))
        #expect(SocketControlSettings.legacyStableDefaultSocketPath == "/tmp/shellx.sock")
        #expect(CmuxConfigStore.defaultGlobalConfigPath().hasSuffix("/.config/shellx/shellx.json"))
        #expect(CmuxSettingsFileStore.defaultPrimaryPath.hasSuffix("/.config/shellx/shellx.json"))
    }

    @Test func socketMarkersAndTaggedSocketsAreShellX() {
        #expect(SocketPathMarkerFiles.stableTmpPath == "/tmp/shellx-last-socket-path")
        #expect(SocketPathMarkerFiles.defaultDebugSocketPath == "/tmp/shellx-debug.sock")
        #expect(
            SocketControlSettings.legacyUserScopedStableSocketPath(currentUserID: 501) == "/tmp/shellx-501.sock"
        )
    }

    @Test func cliIsInstalledAsShellX() {
        let installer = CmuxCLIPathInstaller()
        #expect(installer.destinationPath == "/usr/local/bin/shellx")
    }

    @Test func applicationSupportDirectoryIsShellX() {
        let location = SessionSnapshotFileLocation(
            appSupportDirectory: URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
        )
        #expect(location.cmuxDirectoryURL.lastPathComponent == "ShellX")
    }
}
