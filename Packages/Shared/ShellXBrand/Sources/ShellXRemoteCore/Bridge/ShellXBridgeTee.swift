import Foundation
import os
internal import ShellXRemoteAtomicsC

/// PTY output tee for bridge-bound surfaces. `consume` is called from the app's terminal output
/// callback on the libghostty IO thread for every surface, so the unbound path is one relaxed
/// atomic load: no lock, no allocation. Only a bound surface takes the registry lock and copies
/// its bytes once for its connections.
public enum ShellXBridgeTee {
    private static let registry = OSAllocatedUnfairLock<[UUID: [BridgeConnection]]>(initialState: [:])

    public static func consume(surfaceID: UUID, buffer: UnsafeBufferPointer<UInt8>) {
        guard ShellXBridgeTeeAnyBound() else { return }
        guard buffer.count > 0, buffer.baseAddress != nil,
              let connections = registry.withLock({ $0[surfaceID] }) else { return }
        let bytes = Data(buffer: buffer)
        for connection in connections { connection.teeOutput(bytes) }
    }

    /// Whether any connection receives `surfaceID`'s output (tests and diagnostics).
    public static func isBound(surfaceID: UUID) -> Bool {
        registry.withLock { $0[surfaceID] != nil }
    }

    static func register(_ connection: BridgeConnection, surfaceID: UUID) {
        registry.withLock { map in
            if map[surfaceID]?.contains(where: { $0 === connection }) != true {
                map[surfaceID, default: []].append(connection)
            }
            ShellXBridgeTeeSetAnyBound(!map.isEmpty)
        }
    }

    static func unregister(_ connection: BridgeConnection, surfaceID: UUID) {
        registry.withLock { map in
            map[surfaceID]?.removeAll { $0 === connection }
            if map[surfaceID]?.isEmpty == true { map[surfaceID] = nil }
            ShellXBridgeTeeSetAnyBound(!map.isEmpty)
        }
    }
}
