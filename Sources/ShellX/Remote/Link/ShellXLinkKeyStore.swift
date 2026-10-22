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
    func hostKey() throws -> NoiseStaticKey {
        if let cached = state.withLock({ $0.hostKey }) { return cached }
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        let key: NoiseStaticKey
        if let raw = try OwnerOnlyFile.read(hostKeyURL) {
            key = try NoiseStaticKey(rawPrivate: raw)
        } else {
            key = NoiseStaticKey()
            try OwnerOnlyFile.write(key.rawPrivate, to: hostKeyURL)
        }
        return state.withLock { current in
            if let raced = current.hostKey { return raced }
            current.hostKey = key
            return key
        }
    }

    /// Reads `trusted-clients.json` into memory. A missing file means no trusted phone. Merged, never
    /// replaced: P1 only adds keys, so a key trusted while the file was being read stays trusted.
    func load() throws {
        guard let data = try OwnerOnlyFile.read(trustedURL) else { return }
        let file = try JSONDecoder().decode(TrustedFile.self, from: data)
        let keys = Set(file.clients.compactMap { Data(base64Encoded: $0) }.filter { $0.count == 32 })
        state.withLock { $0.trusted.formUnion(keys) }
    }

    /// Adds a phone's 32-byte static public key to the trusted list and saves the list.
    func trust(_ publicKey: Data) throws {
        let keys = state.withLock { current -> Set<Data> in
            current.trusted.insert(publicKey)
            return current.trusted
        }
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        let file = TrustedFile(clients: keys.map { $0.base64EncodedString() }.sorted())
        try OwnerOnlyFile.write(try JSONEncoder().encode(file), to: trustedURL)
    }

    /// The trusted phones' static public keys, as last loaded or trusted.
    func trustedClients() -> Set<Data> {
        state.withLock { $0.trusted }
    }
}
