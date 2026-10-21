import Foundation
import os

/// Receives a tee'd surface's PTY output. Called on the libghostty IO thread: copy and return fast.
public protocol ShellXTeeSink: AnyObject, Sendable {
    func teeOutput(_ bytes: Data)
}

/// PTY output tee for bound surfaces (bridge connections and share sources). `consume` is called from the app's terminal output
/// callback on the libghostty IO thread for every surface, so the unbound path is one read of an
/// uncontended unfair lock guarding a Bool (writers are the rare bind/unbind): no allocation.
/// Only a bound surface takes the registry lock and copies its bytes once for its sinks.
public enum ShellXBridgeTee {
    private static let anyBound = OSAllocatedUnfairLock(initialState: false)
    private static let registry = OSAllocatedUnfairLock<[UUID: [any ShellXTeeSink]]>(initialState: [:])

    public static func consume(surfaceID: UUID, buffer: UnsafeBufferPointer<UInt8>) {
        guard anyBound.withLock({ $0 }) else { return }
        guard buffer.count > 0, buffer.baseAddress != nil,
              let sinks = registry.withLock({ $0[surfaceID] }) else { return }
        let bytes = Data(buffer: buffer)
        for sink in sinks { sink.teeOutput(bytes) }
    }

    /// Whether any sink receives `surfaceID`'s output (tests and diagnostics).
    public static func isBound(surfaceID: UUID) -> Bool {
        registry.withLock { $0[surfaceID] != nil }
    }

    /// Idempotent per (sink, surface).
    public static func register(_ sink: any ShellXTeeSink, surfaceID: UUID) {
        registry.withLock { map in
            if map[surfaceID]?.contains(where: { $0 === sink }) != true {
                map[surfaceID, default: []].append(sink)
            }
            let bound = !map.isEmpty
            anyBound.withLock { $0 = bound }
        }
    }

    public static func unregister(_ sink: any ShellXTeeSink, surfaceID: UUID) {
        registry.withLock { map in
            map[surfaceID]?.removeAll { $0 === sink }
            if map[surfaceID]?.isEmpty == true { map[surfaceID] = nil }
            let bound = !map.isEmpty
            anyBound.withLock { $0 = bound }
        }
    }
}
