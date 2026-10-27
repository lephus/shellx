import Foundation
import Security
import ShellXAppCore

/// The app's secrets in the data-protection Keychain: this device only, readable after the first
/// unlock, never synced through iCloud.
struct KeychainSecretStore: SecretStore {
    let service: String
    let accessGroup: String?

    init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func read(_ item: SecretItem) throws -> Data? {
        var query = identity(of: item)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw error(for: status)
        }
    }

    func write(_ data: Data, for item: SecretItem) throws {
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(identity(of: item) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = identity(of: item)
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw error(for: status) }
    }

    func delete(_ item: SecretItem) throws {
        let status = SecItemDelete(identity(of: item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(for: status) }
    }

    private func identity(of item: SecretItem) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: item.rawValue,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }

    private func error(for status: OSStatus) -> SecretStoreError {
        status == errSecInteractionNotAllowed ? .unavailable(status: status) : .failed(status: status)
    }
}
