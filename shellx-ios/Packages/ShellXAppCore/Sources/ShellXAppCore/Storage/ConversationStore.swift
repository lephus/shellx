import CryptoKit
import Foundation
import os

/// History kept on this phone as JSON files (plan decision D6): excluded from backup, readable
/// after the first unlock, replaced atomically. A corrupt file is dropped, never fatal. Pending
/// items and agent state are not stored here; they are always fetched from the Mac.
///
/// Writes go through a `Writer` bound to an epoch; `wipe()` ends the epoch, so a write that was in
/// flight at sign-out cannot recreate the previous account's history.
public actor ConversationStore: LocalDataWiping {
    private let directory: URL
    private let maxThreads: Int
    private let now: @Sendable () -> Date
    private var epoch = 0
    /// The newest claim on each document (`writer(claiming:)`).
    private var claims: [StoreDocument: Int] = [:]
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

    /// A writer bound to the store's current epoch. Obtain one when work for the signed-in account
    /// starts (a refresh, a chat subscription) and keep it only for that work: once `wipe()` runs,
    /// every older writer's saves are dropped.
    public func writer() -> Writer { Writer(store: self, epoch: epoch, claim: nil) }

    /// A writer that also claims `doc`: once a newer writer claims the same document, this one's
    /// saves to it are dropped. An agent screen takes one, so when the same session's screen is
    /// popped and pushed again, a late save of the old screen cannot overwrite the new one's.
    public func writer(claiming doc: StoreDocument) -> Writer {
        claims[doc, default: 0] += 1
        return Writer(store: self, epoch: epoch, claim: (doc, claims[doc, default: 0]))
    }

    /// Saves for one epoch of the store (and, for a claiming writer, one claim). Cheap to copy.
    public struct Writer: Sendable {
        fileprivate let store: ConversationStore
        fileprivate let epoch: Int
        fileprivate let claim: (doc: StoreDocument, number: Int)?

        /// Replaces the stored document unless the store was wiped since this writer was made, or a
        /// newer writer claimed the document.
        public func save<T: Encodable & Sendable>(_ value: T, to doc: StoreDocument) async {
            let number = claim.flatMap { $0.doc == doc ? $0.number : nil }
            await store.write(value, to: doc, epoch: epoch, claim: number)
        }

        /// Deletes the stored document (a transcript reset drops the old copy), with the same rules
        /// as `save`: nothing after a wipe, nothing once a newer writer claimed the document.
        public func remove(_ doc: StoreDocument) async {
            let number = claim.flatMap { $0.doc == doc ? $0.number : nil }
            await store.delete(doc, epoch: epoch, claim: number)
        }
    }

    private func delete(_ doc: StoreDocument, epoch writerEpoch: Int, claim: Int?) {
        guard writerEpoch == epoch else {
            log.notice("store_remove_stale kind=\(doc.kind, privacy: .public)")
            return
        }
        if let claim, claims[doc] != claim {
            log.notice("store_remove_superseded kind=\(doc.kind, privacy: .public)")
            return
        }
        let url = fileURL(doc)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log.error("store_remove_failed kind=\(doc.kind, privacy: .public)")
        }
    }

    private func write<T: Encodable & Sendable>(
        _ value: T, to doc: StoreDocument, epoch writerEpoch: Int, claim: Int?
    ) {
        guard writerEpoch == epoch else {
            log.notice("store_write_stale kind=\(doc.kind, privacy: .public)")
            return
        }
        if let claim, claims[doc] != claim {
            log.notice("store_write_superseded kind=\(doc.kind, privacy: .public)")
            return
        }
        do {
            try prepareDirectories()
            let data = try JSONEncoder().encode(value)
            let url = fileURL(doc)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            if case .thread = doc { evictOldThreads(keeping: url) }
        } catch {
            log.error("store_write_failed kind=\(doc.kind, privacy: .public)")
        }
    }

    /// Deletes everything this store holds and invalidates every writer made before. The epoch moves
    /// even when the delete fails, so no stale writer can write afterwards; the failure is thrown.
    public func wipe() throws {
        epoch += 1
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            log.error("store_wipe_failed")
            throw error
        }
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

    /// Keeps the `maxThreads` most recently written thread files; the file just written is never
    /// evicted, even if the clock went backwards.
    private func evictOldThreads(keeping fresh: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: threadsDirectory, includingPropertiesForKeys: keys),
            files.count > maxThreads
        else { return }
        let freshName = fresh.lastPathComponent
        let dated = files.filter { $0.lastPathComponent != freshName }.map { url in
            (url, (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast)
        }
        let oldestFirst = dated.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.lastPathComponent < $1.0.lastPathComponent }
        for (url, _) in oldestFirst.prefix(files.count - maxThreads) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
