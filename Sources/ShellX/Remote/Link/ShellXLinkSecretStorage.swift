import Foundation
import os
import Security
import ShellXRemoteCore

/// Why a secret read or write failed.
enum ShellXLinkSecretError: Error, Equatable, Sendable {
    /// The Keychain is not available right now (`errSecInteractionNotAllowed`, e.g. before the first unlock).
    /// Retrying later can succeed.
    case transient(OSStatus)
    /// The data-protection Keychain refuses this build (`errSecMissingEntitlement`, -34018): ad-hoc signed
    /// tagged and dev builds carry no keychain entitlement. Not corruption, and retrying cannot help.
    case unavailable(OSStatus)
    /// Any other Keychain failure.
    case failed(OSStatus)
}

/// Where the ShellX Link host key and trusted phone list are kept, by account name.
protocol ShellXLinkSecretStorage: Sendable {
    /// The stored bytes, or nil when there is no such item.
    func read(account: String) throws -> Data?
    /// Stores `data` as a new item. Returns false, changing nothing, when the item already exists.
    func add(_ data: Data, account: String) throws -> Bool
    /// Replaces the bytes of an existing item.
    func update(_ data: Data, account: String) throws
}

/// The data-protection Keychain, scoped by bundle id (service) so a tagged or dev build never shares keys
/// with the release build. The account names carry the signed-in ShellX account (see ``ShellXLinkKeyStore``).
struct KeychainLinkSecretStorage: ShellXLinkSecretStorage {
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "pro.shellx.desktop") + ".shellx-link") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    private static func error(_ status: OSStatus) -> ShellXLinkSecretError {
        switch status {
        case errSecInteractionNotAllowed: return .transient(status)
        case errSecMissingEntitlement: return .unavailable(status)
        default: return .failed(status)
        }
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.error(status) }
        guard let data = result as? Data else { throw ShellXLinkSecretError.failed(errSecDecode) }
        return data
    }

    func add(_ data: Data, account: String) throws -> Bool {
        var insert = baseQuery(account)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw Self.error(status) }
        return true
    }

    func update(_ data: Data, account: String) throws {
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw Self.error(status) }
    }
}

/// The bundle id of the production app. Only this build may never fall back to files.
let shellXProductionBundleID = "pro.shellx.desktop"

/// Development-only storage for builds the Keychain refuses (ad-hoc signed tagged builds): one owner-only file
/// per account name under `~/Library/Application Support/ShellX/link-dev/<bundle id>/` (directory `0700`,
/// files `0600`). It is separate from the P1 `ShellX/link/` directory, which is never read.
struct FileLinkSecretStorage: ShellXLinkSecretStorage {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// The directory for `bundleID` under `home`.
    static func directory(home: URL, bundleID: String) -> URL {
        home.appendingPathComponent("Library/Application Support/ShellX/link-dev", isDirectory: true)
            .appendingPathComponent(fileSafe(bundleID), isDirectory: false)
    }

    /// Letters, digits, `.`, `-` and `_` stay; anything else becomes `%XX`; a leading `.` is escaped.
    static func fileSafe(_ name: String) -> String {
        var out = ""
        for (index, byte) in name.utf8.enumerated() {
            let isAlnum = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            if isAlnum || byte == 0x2D || byte == 0x5F || (byte == 0x2E && index > 0) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out.isEmpty ? "%00" : out
    }

    private func url(_ account: String) -> URL {
        directory.appendingPathComponent(Self.fileSafe(account), isDirectory: false)
    }

    func read(account: String) throws -> Data? {
        try OwnerOnlyFile.read(url(account))
    }

    func add(_ data: Data, account: String) throws -> Bool {
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        let target = url(account)
        let temporary = directory.appendingPathComponent("\(UUID().uuidString).tmp", isDirectory: false)
        // Registered first: `write` can throw after its rename and leave the file.
        defer { unlink(temporary.path) }
        try OwnerOnlyFile.write(data, to: temporary)
        if link(temporary.path, target.path) == 0 { return true }
        let code = errno
        guard code == EEXIST else {
            throw OwnerOnlyFileError.io(operation: "link", path: target.path, errno: code)
        }
        return false
    }

    func update(_ data: Data, account: String) throws {
        try OwnerOnlyFile.ensurePrivateDirectory(directory)
        try OwnerOnlyFile.write(data, to: url(account))
    }
}

/// The Keychain, with a development file store behind it for builds the Keychain refuses.
///
/// When the Keychain answers `.unavailable` and a `fallback` was given, this switches to the fallback for good
/// (logging once) and repeats the call there. Without a `fallback` (the production app) the error is thrown.
final class FallbackLinkSecretStorage: ShellXLinkSecretStorage, @unchecked Sendable {
    private let primary: any ShellXLinkSecretStorage
    private let fallback: (any ShellXLinkSecretStorage)?
    private let onFallback: @Sendable () -> Void
    // Lock carve-out: guards one flag, each section only reads or sets it.
    private let usingFallback = OSAllocatedUnfairLock(initialState: false)

    init(primary: any ShellXLinkSecretStorage, fallback: (any ShellXLinkSecretStorage)?,
         onFallback: @escaping @Sendable () -> Void = {}) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    /// The app's storage: the Keychain, plus the development file store unless this is the production bundle.
    static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? shellXProductionBundleID,
                         home: URL = FileManager.default.homeDirectoryForCurrentUser,
                         onFallback: @escaping @Sendable () -> Void = {}) -> FallbackLinkSecretStorage {
        FallbackLinkSecretStorage(
            primary: KeychainLinkSecretStorage(service: bundleID + ".shellx-link"),
            fallback: developmentFallback(bundleID: bundleID, home: home), onFallback: onFallback)
    }

    /// The file store for `bundleID`, or nil for the production bundle: production never falls back.
    static func developmentFallback(bundleID: String, home: URL) -> FileLinkSecretStorage? {
        guard bundleID != shellXProductionBundleID else { return nil }
        return FileLinkSecretStorage(directory: FileLinkSecretStorage.directory(home: home, bundleID: bundleID))
    }

    private func run<T>(_ work: (any ShellXLinkSecretStorage) throws -> T) throws -> T {
        if usingFallback.withLock({ $0 }), let fallback { return try work(fallback) }
        do {
            return try work(primary)
        } catch ShellXLinkSecretError.unavailable(let status) {
            guard let fallback else { throw ShellXLinkSecretError.unavailable(status) }
            let first = usingFallback.withLock { flag -> Bool in
                defer { flag = true }
                return !flag
            }
            if first { onFallback() }
            return try work(fallback)
        }
    }

    func read(account: String) throws -> Data? { try run { try $0.read(account: account) } }
    func add(_ data: Data, account: String) throws -> Bool { try run { try $0.add(data, account: account) } }
    func update(_ data: Data, account: String) throws { try run { try $0.update(data, account: account) } }
}
