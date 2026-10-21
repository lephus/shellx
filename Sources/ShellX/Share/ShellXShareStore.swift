import Foundation
import Security
import ShellXRemoteCore

/// ShellX: a 15 m / 1 h share link kept across a quit so it resumes at the next launch (§7.3). It holds
/// the link secret, so it is stored only in the Keychain, never in UserDefaults or a file.
struct PersistedShare: Codable, Equatable, Sendable {
    /// API form, without the display dash.
    let id: String
    let slot: String
    /// base64url, as in the URL fragment.
    let secret: String
    let permission: SharePermission
    let lifetime: ShareLifetime
    let expiresAt: Date
    let workspaceID: UUID
}

/// The whole list of one account is read and written at once; it holds at most a few entries.
@MainActor
protocol ShellXShareStore: AnyObject {
    func load(account: String) -> [PersistedShare]
    func save(_ shares: [PersistedShare], account: String)
}

/// One generic-password item per account in the data-protection Keychain (like the session-persistence
/// secret), readable after first unlock on this device only.
@MainActor
final class KeychainShellXShareStore: ShellXShareStore {
    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "pro.shellx.desktop") + ".share-links") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "share-links." + account,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load(account: String) -> [PersistedShare] {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return []
        }
        return (try? JSONDecoder().decode([PersistedShare].self, from: data)) ?? []
    }

    func save(_ shares: [PersistedShare], account: String) {
        let baseQuery = baseQuery(account)
        guard !shares.isEmpty else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(shares) else { return }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            if status != errSecSuccess { ShellXShareController.log.error("share store update failed: \(status)") }
            return
        }
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added != errSecSuccess { ShellXShareController.log.error("share store add failed: \(added)") }
    }
}
