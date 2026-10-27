import Foundation
import Security

/// Why a secret read or write failed.
enum ShellXLinkSecretError: Error, Equatable, Sendable {
    /// The Keychain is not available right now (`errSecInteractionNotAllowed`, e.g. before the first unlock).
    /// Retrying later can succeed.
    case transient(OSStatus)
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
        status == errSecInteractionNotAllowed ? .transient(status) : .failed(status)
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
