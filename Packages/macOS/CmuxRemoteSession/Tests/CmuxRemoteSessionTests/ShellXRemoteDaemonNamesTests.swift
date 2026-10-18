import Foundation
import Testing
@testable import CmuxRemoteSession

// ShellX uploads its own SSH helper (`shellx-remote`) under `~/.shellx` on the
// remote host, so it never overwrites, reuses or reaps an installed cmux's
// helper on the same host. Release builds never honor the dev-only local
// binary / `go build` fallback.
@Suite("ShellX remote daemon names")
struct ShellXRemoteDaemonNamesTests {
    @Test("The helper installs under ~/.shellx/bin/shellx-remote")
    func installPathIsShellX() {
        #expect(
            RemoteSessionCoordinator.remoteDaemonPath(version: "1.2.3", goOS: "linux", goArch: "amd64")
                == ".shellx/bin/shellx-remote/1.2.3/linux-amd64/shellx-remote"
        )
        let probe = RemoteSessionCoordinator.remotePlatformProbeScript(version: "1.2.3")
        #expect(probe.contains("\"$HOME/.shellx/bin/shellx-remote/1.2.3/${cmux_go_os}-${cmux_go_arch}/shellx-remote\""))
        #expect(!probe.contains(".cmux"))
        #expect(
            RemoteSessionCoordinator.versionedRemoteDaemonBuildURL(goOS: "linux", goArch: "arm64", version: "1")
                .lastPathComponent == "shellx-remote"
        )
    }

    @Test("Relay metadata, CLI wrapper and daemon link live under ~/.shellx")
    func relayProvisioningIsShellX() {
        let install = RemoteSessionCoordinator.remoteRelayMetadataInstallScript(
            daemonRemotePath: ".shellx/bin/shellx-remote/1/linux-amd64/shellx-remote",
            relayPort: 64044,
            relayID: "relay",
            relayToken: "token",
            persistentDaemonSlot: "ssh-slot"
        )
        #expect(install.contains("\"$HOME/.shellx/relay/64044.auth\""))
        #expect(install.contains("\"$HOME/.shellx/relay/64044.slot\""))
        #expect(install.contains("> \"$HOME/.shellx/socket_addr\""))
        #expect(install.contains("ln -sf \"$HOME/.shellx/bin/shellx-remote/1/linux-amd64/shellx-remote\" \"$HOME/.shellx/bin/shellx-remote-current\""))
        #expect(install.contains("mv -f \"$wrapper_tmp\" \"$HOME/.shellx/bin/shellx\""))
        #expect(!install.contains(".cmux/"))

        let wrapper = RemoteSessionCoordinator.remoteCLIWrapperScript()
        #expect(wrapper.contains("daemon=\"$HOME/.shellx/bin/shellx-remote-current\""))
        #expect(wrapper.contains("relay_map=\"$HOME/.shellx/relay/${relay_port}.daemon_path\""))
        #expect(!wrapper.contains(".cmux/"))

        for cleanup in [
            RemoteSessionCoordinator.remoteRelayMetadataCleanupScript(relayPort: 64044, persistentDaemonSlot: "ssh-slot"),
            RemoteSessionCoordinator.remoteRelayTransportMetadataCleanupScript(relayPort: 64044, persistentDaemonSlot: nil),
            RemoteSessionCoordinator.remoteRelayMetadataOwnershipProbeScript(
                relayPort: 64044, relayID: "relay", relayToken: "token", persistentDaemonSlot: nil
            ),
        ] {
            #expect(cleanup.contains("relay_directory=\"$HOME/.shellx/relay\""))
            #expect(!cleanup.contains(".cmux/"))
        }
    }

    @Test("Orphan cleanup reaps ShellX's helper transports, never cmux's")
    func orphanCleanupMatchesOnlyShellX() {
        let ps = """
          101 1 /usr/bin/ssh -T -S none -o RequestTTY=no host sh -c 'exec .shellx/bin/shellx-remote/1/linux-amd64/shellx-remote serve --stdio'
          102 1 /usr/bin/ssh -T -S none -o RequestTTY=no host sh -c 'exec .cmux/bin/cmuxd-remote/0.63.1/linux-amd64/cmuxd-remote serve --stdio'
        """
        #expect(RemoteSessionCoordinator.orphanedCMUXRemoteSSHPIDs(psOutput: ps, destination: "host") == [101])
    }

    @Test("Release builds ignore the dev-only daemon fallback")
    func releaseBuildsIgnoreDevFallback() {
        let environment = [
            "CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD": "1",
            "CMUX_REMOTE_DAEMON_BINARY": "/tmp/dist/shellx-remote-linux-amd64",
        ]
        #expect(!RemoteSessionCoordinator.allowLocalDaemonBuildFallback(environment: environment, isDebugBuild: false))
        #expect(RemoteSessionCoordinator.explicitRemoteDaemonBinaryURL(environment: environment, isDebugBuild: false) == nil)

        #expect(RemoteSessionCoordinator.allowLocalDaemonBuildFallback(environment: environment, isDebugBuild: true))
        #expect(
            RemoteSessionCoordinator.explicitRemoteDaemonBinaryURL(environment: environment, isDebugBuild: true)?.path
                == "/tmp/dist/shellx-remote-linux-amd64"
        )
        #expect(!RemoteSessionCoordinator.allowLocalDaemonBuildFallback(environment: [:], isDebugBuild: true))
        // `swift test` builds the Debug configuration, where DEBUG is defined.
        #expect(RemoteSessionCoordinator.isDebugBuild)
    }
}
