import CryptoKit
import Foundation
import os

/// History kept on this phone as JSON files (plan decision D6): excluded from backup, readable
/// after the first unlock, replaced atomically. A corrupt file is dropped, never fatal. Pending
/// items and agent state are not stored here; they are always fetched from the Mac.
public actor ConversationStore: LocalDataWiping {
    private let directory: URL
    private let maxThreads: Int
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: "com.shellx.app", category: "store")

    public init(directory: URL, maxThreads: Int = 100, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maxThreads = maxThreads
        self.now = now
    }

    /// The stored document, or nil when there is none or it is unreadable (an unreadable file is
    /// removed).
    public func load<T: Decodable & Sendable>(_ doc: StoreDocument, as type: T.Type) -> T? {
        let url = fileURL(doc)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log.notice("store_corrupt kind=\(doc.kind, privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Replaces the stored document. A failed write is logged by kind only and leaves the old file.
    public func save<T: Encodable & Sendable>(_ value: T, to doc: StoreDocument) {
        do {
            try prepareDirectories()
            let data = try JSONEncoder().encode(value)
            let url = fileURL(doc)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            if case .thread = doc { evictOldThreads() }
        } catch {
            log.error("store_write_failed kind=\(doc.kind, privacy: .public)")
        }
    }

    /// Deletes everything this store holds.
    public func wipe() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    private var threadsDirectory: URL { directory.appendingPathComponent("threads", isDirectory: true) }

    private func fileURL(_ doc: StoreDocument) -> URL {
        switch doc {
        case .home: return directory.appendingPathComponent("home.json")
        case .lastSessions: return directory.appendingPathComponent("last-sessions.json")
        case .thread(let ref):
            let digest = SHA256.hash(data: Data("\(ref.machineID)\0\(ref.sessionId)".utf8))
            let name = digest.map { String(format: "%02x", $0) }.joined()
            return threadsDirectory.appendingPathComponent("\(name).json")
        }
    }
    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: threadsDirectory, withIntermediateDirectories: true)
        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    /// Keeps the `maxThreads` most recently written thread files.
    private func evictOldThreads() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: threadsDirectory, includingPropertiesForKeys: keys),
            files.count > maxThreads
        else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast)
        }
        let oldestFirst = dated.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.lastPathComponent < $1.0.lastPathComponent }
        for (url, _) in oldestFirst.prefix(files.count - maxThreads) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
