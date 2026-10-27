import Foundation
import os
import Security
import ShellXLinkCore

/// A phone this Mac lets in over ShellX Link.
struct TrustedPhone: Equatable, Sendable {
    /// The phone's 32-byte static public key.
    let key: Data
    let deviceID: String
    let name: String
    let pairedAt: Date
}

/// ShellX: the Mac's ShellX Link identity and the phones it trusts, in secret storage (the Keychain in the
/// app), one set per signed-in ShellX account.
///
/// * `host-key.<accountID>`: the 32-byte X25519 private key, created on first use.
/// * `trusted-clients.<accountID>`: `{"version": 2, "phones": [{"key", "device_id", "name", "paired_at"}]}`.
///
/// The P1 files under `~/Library/Application Support/ShellX/link/` are neither read nor deleted.
/// Storage calls block, so ``hostKey()``, ``load()`` and the mutators run off the main thread.
/// ``trustedClients()`` only reads memory and is safe from any thread.
final class ShellXLinkKeyStore: Sendable {
    private struct StoredPhone: Codable {
        var key: String
        var deviceID: String
        var name: String
        var pairedAt: Date

        enum CodingKeys: String, CodingKey {
            case key, name
            case deviceID = "device_id"
            case pairedAt = "paired_at"
        }
    }

    private struct TrustedFile: Codable {
        var version = 2
        var phones: [StoredPhone]
    }

    private struct State: Sendable {
        var hostKey: NoiseStaticKey?
        var trusted: [Data: TrustedPhone] = [:]
    }

    private let storage: any ShellXLinkSecretStorage
    private let hostAccount: String
    private let trustedAccount: String

    // Lock carve-out: `LinkHost` reads the trusted keys through a synchronous `@Sendable () -> Set<Data>`
    // closure on every handshake, from its own executor. Each critical section only copies a value.
    private let state = OSAllocatedUnfairLock(initialState: State())
    // Lock carve-out: serializes this store's read-modify-write of the stored items. The callers are
    // synchronous blocks on global queues (`offMain`), so an actor would add a hop at every call site; the
    // section blocks on Keychain I/O, which an unfair lock must not do. Never taken by `trustedClients()`.
    private let storageLock = NSLock()

    /// - Parameters:
    ///   - storage: Where the items live.
    ///   - accountID: The signed-in ShellX account; another account has another host key and phone list.
    init(storage: any ShellXLinkSecretStorage, accountID: String) {
        self.storage = storage
        hostAccount = "host-key.\(accountID)"
        trustedAccount = "trusted-clients.\(accountID)"
    }

    // MARK: - Host key

    /// The host's static key: read from storage, or created and added there on first use.
    ///
    /// A corrupt item throws; it is never replaced. First-time creation uses `add`, which fails when
    /// another caller created the item first; the key stored then wins, so every caller uses one key.
    func hostKey() throws -> NoiseStaticKey {
        if let cached = state.withLock({ $0.hostKey }) { return cached }
        storageLock.lock()
        defer { storageLock.unlock() }
        if let cached = state.withLock({ $0.hostKey }) { return cached }
        let key = try readHostKey() ?? createHostKey()
        state.withLock { $0.hostKey = key }
        return key
    }

    private func readHostKey() throws -> NoiseStaticKey? {
        guard let raw = try storage.read(account: hostAccount) else { return nil }
        return try NoiseStaticKey(rawPrivate: raw)
    }

    private func createHostKey() throws -> NoiseStaticKey {
        let candidate = NoiseStaticKey()
        if try storage.add(candidate.rawPrivate, account: hostAccount) { return candidate }
        guard let existing = try readHostKey() else { throw ShellXLinkSecretError.failed(errSecItemNotFound) }
        return existing
    }

    // MARK: - Trusted phones

    /// Reads the trusted list from storage into memory, replacing what memory held. A missing item means
    /// no trusted phone; a corrupt one throws and is left as it is.
    func load() throws {
        storageLock.lock()
        defer { storageLock.unlock() }
        _ = try loadLocked()
    }

    private func loadLocked() throws -> [Data: TrustedPhone] {
        var phones: [Data: TrustedPhone] = [:]
        if let data = try storage.read(account: trustedAccount) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for stored in try decoder.decode(TrustedFile.self, from: data).phones {
                guard let key = Data(base64Encoded: stored.key), key.count == 32 else { continue }
                phones[key] = TrustedPhone(key: key, deviceID: stored.deviceID, name: stored.name,
                                           pairedAt: stored.pairedAt)
            }
        }
        state.withLock { $0.trusted = phones }
        return phones
    }

    private func saveLocked(_ phones: [Data: TrustedPhone]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let stored = phones.values.sorted { $0.key.base64EncodedString() < $1.key.base64EncodedString() }
            .map { StoredPhone(key: $0.key.base64EncodedString(), deviceID: $0.deviceID, name: $0.name,
                               pairedAt: $0.pairedAt) }
        let data = try encoder.encode(TrustedFile(phones: stored))
        if try !storage.add(data, account: trustedAccount) {
            try storage.update(data, account: trustedAccount)
        }
        state.withLock { $0.trusted = phones }
    }

    /// Adds `phone` (or replaces the entry with the same key) and saves the list. The stored list is read
    /// first, so phones trusted earlier survive even when ``load()`` has not run yet.
    func trust(_ phone: TrustedPhone) throws {
        guard phone.key.count == 32 else { throw ShellXLinkSecretError.failed(errSecParam) }
        storageLock.lock()
        defer { storageLock.unlock() }
        var phones = try loadLocked()
        phones[phone.key] = phone
        try saveLocked(phones)
    }

    /// Removes the phone with `key` and saves the list.
    func untrust(key: Data) throws {
        storageLock.lock()
        defer { storageLock.unlock() }
        var phones = try loadLocked()
        guard phones.removeValue(forKey: key) != nil else { return }
        try saveLocked(phones)
    }

    /// Drops every trusted phone whose key is not in `keys`. It only removes, never adds: a key in `keys`
    /// that is not trusted stays untrusted.
    ///
    /// - Returns: The keys that were removed.
    @discardableResult
    func retainOnly(keys: Set<Data>) throws -> Set<Data> {
        storageLock.lock()
        defer { storageLock.unlock() }
        let phones = try loadLocked()
        let kept = phones.filter { keys.contains($0.key) }
        let removed = Set(phones.keys).subtracting(kept.keys)
        guard !removed.isEmpty else { return [] }
        try saveLocked(kept)
        return removed
    }

    /// The trusted phones' static public keys, as last loaded or trusted.
    func trustedClients() -> Set<Data> {
        state.withLock { Set($0.trusted.keys) }
    }

    /// The trusted phones, as last loaded or trusted, oldest pairing first.
    func trustedPhones() -> [TrustedPhone] {
        state.withLock { $0.trusted.values.sorted { $0.pairedAt < $1.pairedAt } }
    }
}
