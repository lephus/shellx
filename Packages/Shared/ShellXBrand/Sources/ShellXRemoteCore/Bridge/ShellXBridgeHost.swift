import Foundation

/// The daemon's `H` frame (`cmux-tui-core/src/virtual_pty.rs`): `{"protocol":1,"cols","rows","cwd"}`,
/// plus the server's id for the connection it arrived on.
public struct BridgeHello: Equatable, Sendable {
    public static let supportedProtocol = 1
    /// Longest `cwd` passed on to the host (macOS `PATH_MAX` is 1024); a longer one is dropped.
    public static let maxCwdBytes = 4096

    public let connectionID: Int
    public let protocolVersion: Int
    public let cols: UInt16
    public let rows: UInt16
    public let cwd: String?

    public init(connectionID: Int, protocolVersion: Int, cols: UInt16, rows: UInt16, cwd: String?) {
        self.connectionID = connectionID
        self.protocolVersion = protocolVersion
        self.cols = cols
        self.rows = rows
        self.cwd = cwd
    }

    private struct Wire: Decodable {
        let protocolVersion: Int
        let cols: Int
        let rows: Int
        let cwd: String?

        enum CodingKeys: String, CodingKey { case protocolVersion = "protocol", cols, rows, cwd }
    }

    /// A well-formed hello of a supported protocol, or nil.
    static func parse(_ payload: Data, connectionID: Int) -> BridgeHello? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: payload),
              wire.protocolVersion == supportedProtocol,
              let cols = UInt16(exactly: wire.cols), let rows = UInt16(exactly: wire.rows) else { return nil }
        let cwd = wire.cwd.flatMap { $0.utf8.count <= maxCwdBytes && !$0.utf8.contains(0) ? $0 : nil }
        return BridgeHello(connectionID: connectionID, protocolVersion: wire.protocolVersion, cols: cols, rows: rows, cwd: cwd)
    }
}

/// One daemon terminal bound to one Mac terminal surface. `mode` is `"attach"` (projects the
/// focused terminal) or `"create"` (a new tab), D7.
public struct BridgeBinding: Hashable, Sendable {
    public let connectionID: Int
    public let surfaceID: UUID
    public let workspaceID: UUID
    public let mode: String

    public init(connectionID: Int, surfaceID: UUID, workspaceID: UUID, mode: String) {
        self.connectionID = connectionID
        self.surfaceID = surfaceID
        self.workspaceID = workspaceID
        self.mode = mode
    }

    /// The `A` frame payload `{"surface_id","workspace_id","mode"}`.
    var ackPayload: Data {
        let object = ["surface_id": surfaceID.uuidString, "workspace_id": workspaceID.uuidString, "mode": mode]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

/// The Mac side of the bridge: real terminals. Every call is made on the main actor by
/// `ShellXBridgeServer`; the server never closes a Mac surface (D7), it only unbinds.
@MainActor
public protocol ShellXBridgeHost: AnyObject, Sendable {
    /// Binds the daemon terminal of `hello` to a Mac terminal (`hello.connectionID` is the
    /// binding's `connectionID`), or nil to refuse it.
    func bind(hello: BridgeHello) -> BridgeBinding?
    /// Remote input, byte exact as received (never decoded as text).
    func input(_ bytes: Data, binding: BridgeBinding)
    /// The daemon's resize wish; the Mac owns the PTY and decides the real grid.
    func remoteResize(cols: UInt16, rows: UInt16, binding: BridgeBinding)
    /// The bound surface's real grid, or nil when the surface is gone.
    func grid(binding: BridgeBinding) -> (cols: UInt16, rows: UInt16)?
    /// Screen snapshot sent before live output (attach only; nil for a created tab).
    func snapshot(binding: BridgeBinding) -> Data?
    /// Ends the binding without closing the Mac surface.
    func unbind(_ binding: BridgeBinding)
}
