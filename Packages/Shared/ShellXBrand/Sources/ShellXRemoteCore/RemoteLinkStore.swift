import Foundation

/// What a viewer keeps per remote machine: where to reach its daemon and whether this Mac is enrolled.
/// Holds no secret (tickets and invites stay in shellx-core's state dir).
public struct RemoteLinkRecord: Codable, Equatable, Sendable {
    public var machineID: String
    public var route: String
    public var slot: String
    public var daemonFingerprint: String
    public var enrolled: Bool

    public init(machineID: String, route: String, slot: String, daemonFingerprint: String, enrolled: Bool) {
        self.machineID = machineID; self.route = route; self.slot = slot
        self.daemonFingerprint = daemonFingerprint; self.enrolled = enrolled
    }
}

/// `stateRoot/links.json`, written owner-only (`OwnerOnlyFile`).
public struct RemoteLinkStore: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }
    public init(paths: RemotePaths) { self.init(file: paths.stateRoot.appendingPathComponent("links.json")) }

    /// Serialises read-modify-write between link supervisors in this process.
    private static let lock = NSLock()

    public func load() throws -> [RemoteLinkRecord] {
        guard let data = try OwnerOnlyFile.read(file) else { return [] }
        return try JSONDecoder().decode([RemoteLinkRecord].self, from: data)
    }

    public func save(_ records: [RemoteLinkRecord]) throws {
        try OwnerOnlyFile.ensurePrivateDirectory(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try OwnerOnlyFile.write(try encoder.encode(records), to: file)
    }

    /// Replaces the record with the same `machineID`, or appends it.
    public func upsert(_ record: RemoteLinkRecord) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var records = try load()
        if let index = records.firstIndex(where: { $0.machineID == record.machineID }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try save(records)
    }

    /// Drops the record of `machineID` (a grant whose first enrollment can no longer succeed).
    public func remove(machineID: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let records = try load()
        let kept = records.filter { $0.machineID != machineID }
        if kept.count != records.count { try save(kept) }
    }
}
