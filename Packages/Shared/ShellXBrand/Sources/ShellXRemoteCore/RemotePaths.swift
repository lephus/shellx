import Foundation

/// Per-bundle state and socket locations, so a Release and a tagged debug build never share anything.
public struct RemotePaths: Equatable, Sendable {
    public let stateRoot, coreStateDir, daemonStateDir, clientStateDir: URL
    public let socketDir, muxSocket, bridgeSocket, adminSocket, linkSocket: URL
    public let session: String

    public init(bundleID: String, home: URL, temporaryDirectory: URL) {
        let h = SHA256Pure.hash8(bundleID)
        stateRoot = home.appendingPathComponent("Library/Application Support/ShellX/remote/\(bundleID)", isDirectory: true)
        coreStateDir = stateRoot.appendingPathComponent("core", isDirectory: true)
        daemonStateDir = stateRoot.appendingPathComponent("daemon", isDirectory: true)
        clientStateDir = stateRoot.appendingPathComponent("client", isDirectory: true)
        socketDir = temporaryDirectory.appendingPathComponent("sx-\(h)", isDirectory: true)
        muxSocket = socketDir.appendingPathComponent("mux.sock")
        bridgeSocket = socketDir.appendingPathComponent("bridge.sock")
        adminSocket = socketDir.appendingPathComponent("admin.sock")
        linkSocket = socketDir.appendingPathComponent("link.sock")
        session = "shellx-\(h)"
    }

    public func clientSocket(for machine: RemoteMachine.ID) -> URL {
        socketDir.appendingPathComponent("c-\(SHA256Pure.hash8(machine)).sock")
    }

    public func connectTicketName(for machine: RemoteMachine.ID) -> String {
        "connect-\(SHA256Pure.hash8(machine)).ticket"
    }
}
