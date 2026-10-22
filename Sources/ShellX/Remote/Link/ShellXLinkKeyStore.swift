import Darwin
import Foundation
import os
import ShellXLinkCore
import ShellXRemoteCore

/// ShellX: the Mac's ShellX Link identity and the phones it trusts, under
/// `~/Library/Application Support/ShellX/link/` (directory `0700`, files `0600`).
///
/// * `host-key`: the 32-byte X25519 private key, created on first use.
/// * `trusted-clients.json`: `{"version": 1, "clients": ["<base64 public key>", ...]}`.
///
/// P1 spike storage; P2 moves both into the Keychain together with real pairing. File I/O blocks, so
/// ``hostKey()``, ``load()`` and ``trust(_:)`` run off the main thread. ``trustedClients()`` only reads
/// memory and is safe from any thread.
final class ShellXLinkKeyStore: Sendable {
    private struct TrustedFile: Codable {
        var version = 1
        var clients: [String]
    }

    private struct State: Sendable {
        var hostKey: NoiseStaticKey?
        var trusted: Set<Data> = []
    }

    let directory: URL
    private var hostKeyURL: URL { directory.appendingPathComponent("host-key", isDirectory: false) }
    private var trustedURL: URL { directory.appendingPathComponent("trusted-clients.json", isDirectory: false) }

    // Lock carve-out: `LinkHost` reads the trusted keys through a synchronous `@Sendable () -> Set<Data>`
    // closure on every handshake, from its own executor. Each critical section only copies a value.
    private let state = OSAllocatedUnfairLock(initialState: State())
    // Lock carve-out: serializes this store's read-modify-write of its files (first host key, trusted list).
    // The callers are synchronous blocks on global queues (`offMain`), so an actor would add a hop at every
    // call site; the section blocks on file I/O, which an unfair lock must not do. Never taken by
    // `trustedClients()`.
    private let fileLock = NSLock()

    /// - Parameter directory: The link state directory (the app passes
    ///   `~/Library/Application Support/ShellX/link`; tests pass a temp directory).
    init(directory: URL) {
        self.directory = directory
    }

    /// The default directory for `home`.
    static func defaultDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/ShellX/link", isDirectory: true)
    }

    /// The host's static key: read from `host-key`, or created and saved there on first use.
    ///
    /// A corrupt file throws; it is never replaced. First-time creation is exclusive: the new key is
    /// written to a private temporary file and hard-linked to `host-key`, which fails if another process
    /// created it first, and then that key is read back. Every caller therefore uses the key on disk.
    func hostKey() throws -> NoiseStaticKey {
        if let cached = state.withLock({ $0.hostKey }) { return cached }
        fileLock.lock()
        defer { fileLock.unlock() }
        if let cached = state.withLock({ $0.hostKey }) { return cached }
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        let key = try readHostKey() ?? createHostKey()
        state.withLock { $0.hostKey = key }
        return key
    }

    private func readHostKey() throws -> NoiseStaticKey? {
        guard let raw = try OwnerOnlyFile.read(hostKeyURL) else { return nil }
        return try NoiseStaticKey(rawPrivate: raw)
    }

    private func createHostKey() throws -> NoiseStaticKey {
        let candidate = NoiseStaticKey()
        let temporary = directory.appendingPathComponent("host-key.\(UUID().uuidString).tmp", isDirectory: false)
        try OwnerOnlyFile.write(candidate.rawPrivate, to: temporary)
        defer { unlink(temporary.path) }
        if link(temporary.path, hostKeyURL.path) == 0 { return candidate }
        let code = errno
        guard code == EEXIST, let existing = try readHostKey() else {
            throw OwnerOnlyFileError.io(operation: "link", path: hostKeyURL.path, errno: code)
        }
        return existing
    }

    /// Reads `trusted-clients.json` into memory. A missing file means no trusted phone. Merged, never
    /// replaced: P1 only adds keys, so a key trusted while the file was being read stays trusted.
    func load() throws {
        fileLock.lock()
        defer { fileLock.unlock() }
        try loadLocked()
    }

    private func loadLocked() throws {
        guard let data = try OwnerOnlyFile.read(trustedURL) else { return }
        let file = try JSONDecoder().decode(TrustedFile.self, from: data)
        let keys = Set(file.clients.compactMap { Data(base64Encoded: $0) }.filter { $0.count == 32 })
        state.withLock { $0.trusted.formUnion(keys) }
    }

    /// Adds a phone's 32-byte static public key to the trusted list and saves the list. The list on disk
    /// is read first, so phones trusted earlier survive even when ``load()`` has not run yet.
    func trust(_ publicKey: Data) throws {
        fileLock.lock()
        defer { fileLock.unlock() }
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        try loadLocked()
        let keys = state.withLock { current -> Set<Data> in
            current.trusted.insert(publicKey)
            return current.trusted
        }
        let file = TrustedFile(clients: keys.map { $0.base64EncodedString() }.sorted())
        try OwnerOnlyFile.write(try JSONEncoder().encode(file), to: trustedURL)
    }

    /// The trusted phones' static public keys, as last loaded or trusted.
    func trustedClients() -> Set<Data> {
        state.withLock { $0.trusted }
    }
}
