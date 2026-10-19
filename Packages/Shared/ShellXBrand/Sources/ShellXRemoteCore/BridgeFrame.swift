import Foundation

public enum BridgeFrameType: UInt8, Sendable {
    case hello = 0x48, input = 0x49, resize = 0x52, kill = 0x4B, ack = 0x41, output = 0x4F, size = 0x53, exit = 0x45
}

public enum BridgeFrameError: Error, Equatable, Sendable { case oversize(Int), unknownType(UInt8) }

/// `[type u8][len u32 BE][payload]`, payload at most 16 MiB (`cmux-tui-core/src/virtual_pty.rs`).
public struct BridgeFrame: Equatable, Sendable {
    public let type: BridgeFrameType
    public let payload: Data

    public init(type: BridgeFrameType, payload: Data) { self.type = type; self.payload = payload }

    public func encoded() -> Data {
        var out = Data(capacity: 5 + payload.count)
        out.append(type.rawValue)
        let n = UInt32(truncatingIfNeeded: payload.count)
        out.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        out.append(payload)
        return out
    }

    public static func size(cols: UInt16, rows: UInt16) -> BridgeFrame {
        BridgeFrame(type: .size, payload: Data([UInt8(cols >> 8), UInt8(cols & 0xff), UInt8(rows >> 8), UInt8(rows & 0xff)]))
    }
}

/// Incremental decoder; payload bytes are never interpreted, so split UTF-8 stays byte exact.
public struct BridgeFrameDecoder: Sendable {
    public static let maxPayload = 16 << 20
    private var buffer = [UInt8]()

    public init() {}

    public mutating func feed(_ bytes: Data) throws -> [BridgeFrame] {
        buffer.append(contentsOf: bytes)
        var frames: [BridgeFrame] = []
        var offset = 0
        while buffer.count - offset >= 5 {
            let raw = buffer[offset]
            guard let type = BridgeFrameType(rawValue: raw) else { throw BridgeFrameError.unknownType(raw) }
            let len = Int(UInt32(buffer[offset + 1]) << 24 | UInt32(buffer[offset + 2]) << 16
                          | UInt32(buffer[offset + 3]) << 8 | UInt32(buffer[offset + 4]))
            guard len <= Self.maxPayload else { throw BridgeFrameError.oversize(len) }
            guard buffer.count - offset - 5 >= len else { break }
            frames.append(BridgeFrame(type: type, payload: Data(buffer[(offset + 5)..<(offset + 5 + len)])))
            offset += 5 + len
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return frames
    }
}
