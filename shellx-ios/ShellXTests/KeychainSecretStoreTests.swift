import Security
import ShellXAppCore
import XCTest
@testable import ShellX

final class KeychainSecretStoreTests: XCTestCase {
    private var service = ""
    private var store: KeychainSecretStore!

    override func setUp() {
        super.setUp()
        service = "com.shellx.dev.tests.\(UUID().uuidString)"
        store = KeychainSecretStore(service: service, accessGroup: nil)
    }

    override func tearDown() {
        for item in SecretItem.allCases { try? store.delete(item) }
        super.tearDown()
    }

    func testWriteReadDelete() throws {
        XCTAssertNil(try store.read(.session))
        try store.write(Data("one".utf8), for: .session)
        XCTAssertEqual(try store.read(.session), Data("one".utf8))
        try store.write(Data("two".utf8), for: .session)
        XCTAssertEqual(try store.read(.session), Data("two".utf8), "write replaces")
        try store.delete(.session)
        XCTAssertNil(try store.read(.session))
        XCTAssertNoThrow(try store.delete(.session), "deleting a missing item is not an error")
    }

    func testItemIsThisDeviceOnlyAfterFirstUnlock() throws {
        try store.write(Data("k".utf8), for: .phoneKey)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: SecretItem.phoneKey.rawValue,
            kSecUseDataProtectionKeychain: true,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        let synchronizable = attributes[kSecAttrSynchronizable as String] as? Bool
        XCTAssertTrue(synchronizable == nil || synchronizable == false, "never synced through iCloud")
    }
}
