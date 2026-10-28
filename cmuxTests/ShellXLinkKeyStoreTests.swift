import Foundation
import Security
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// In-memory stand-in for the Keychain: same add / update / read contract, no OS dependency.
final class InMemoryLinkSecretStorage: ShellXLinkSecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var readFailures: [ShellXLinkSecretError]
    private var failWrites = false

    init(readFailures: [ShellXLinkSecretError] = []) { self.readFailures = readFailures }

    func read(account: String) throws -> Data? {
        try lock.withLock {
            if !readFailures.isEmpty { throw readFailures.removeFirst() }
            return items[account]
        }
    }

    func setWriteFailure(_ fail: Bool) { lock.withLock { failWrites = fail } }

    func add(_ data: Data, account: String) throws -> Bool {
        if lock.withLock({ failWrites }) { throw ShellXLinkSecretError.failed(-1) }
        return lock.withLock {
            if items[account] != nil { return false }
            items[account] = data
            return true
        }
    }

    func update(_ data: Data, account: String) throws {
        if lock.withLock({ failWrites }) { throw ShellXLinkSecretError.failed(-1) }
        try lock.withLock {
            guard items[account] != nil else { throw ShellXLinkSecretError.failed(-25300) }
            items[account] = data
        }
    }

    func raw(_ account: String) -> Data? { lock.withLock { items[account] } }
    func set(_ data: Data, account: String) { lock.withLock { items[account] = data } }
}

/// The Mac's ShellX Link host key and trusted phones live in secret storage, scoped by account.
struct ShellXLinkKeyStoreTests {
    private static func phone(_ byte: UInt8, name: String = "Phone") -> TrustedPhone {
        TrustedPhone(key: Data(repeating: byte, count: 32), deviceID: "dev-\(byte)", name: name,
                     pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func testHostKeyScopedByAccount() throws {
        let storage = InMemoryLinkSecretStorage()
        let a = try ShellXLinkKeyStore(storage: storage, accountID: "acct-a").hostKey()
        let again = try ShellXLinkKeyStore(storage: storage, accountID: "acct-a").hostKey()
        let b = try ShellXLinkKeyStore(storage: storage, accountID: "acct-b").hostKey()

        #expect(a.publicKey.count == 32)
        #expect(again.publicKey == a.publicKey)
        #expect(b.publicKey != a.publicKey)
        #expect(storage.raw("host-key.acct-a") != nil)
        #expect(storage.raw("host-key.acct-b") != nil)
    }

    @Test func testConcurrentFirstHostKeyUsesStoredOne() throws {
        let storage = InMemoryLinkSecretStorage()
        // Separate stores sharing one storage race on the first `add`; the loser must read the winner's key.
        let stores = (0..<4).map { _ in ShellXLinkKeyStore(storage: storage, accountID: "acct") }
        let keys = Box<Data>()

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            if let key = try? stores[index % stores.count].hostKey() { keys.add(key.publicKey) }
        }

        #expect(keys.all.count == 16)
        #expect(Set(keys.all).count == 1)
        #expect(try ShellXLinkKeyStore(storage: storage, accountID: "acct").hostKey().publicKey == keys.all.first)
    }

    @Test func testTrustUntrustPersist() throws {
        let storage = InMemoryLinkSecretStorage()
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let one = Self.phone(1, name: "One"), two = Self.phone(2, name: "Two")
        #expect(store.trustedClients().isEmpty)
        try store.trust(one)
        try store.trust(two)

        let reloaded = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try reloaded.load()
        #expect(reloaded.trustedClients() == [one.key, two.key])
        #expect(reloaded.trustedPhones().map(\.name).sorted() == ["One", "Two"])
        #expect(reloaded.trustedPhones().first { $0.key == one.key } == one)

        try reloaded.untrust(key: one.key)
        let again = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try again.load()
        #expect(again.trustedClients() == [two.key])
        // Another account never sees it.
        let other = ShellXLinkKeyStore(storage: storage, accountID: "other")
        try other.load()
        #expect(other.trustedClients().isEmpty)

        let json = try #require(storage.raw("trusted-clients.acct"))
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["version"] as? Int == 2)
        let entry = try #require((object["phones"] as? [[String: Any]])?.first)
        #expect(Set(entry.keys) == ["key", "device_id", "name", "paired_at"])
    }

    @Test func testTrustBeforeLoadKeepsPhonesAlreadyStored() throws {
        let storage = InMemoryLinkSecretStorage()
        try ShellXLinkKeyStore(storage: storage, accountID: "acct").trust(Self.phone(1))
        try ShellXLinkKeyStore(storage: storage, accountID: "acct").trust(Self.phone(2))   // no load() first
        let reloaded = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try reloaded.load()
        #expect(reloaded.trustedClients() == [Self.phone(1).key, Self.phone(2).key])
    }

    @Test func testRetainOnlyNeverAdds() throws {
        let storage = InMemoryLinkSecretStorage()
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try store.trust(Self.phone(1))
        try store.trust(Self.phone(2))
        let stranger = Data(repeating: 9, count: 32)

        try store.retainOnly(keys: [Self.phone(2).key, stranger])

        #expect(store.trustedClients() == [Self.phone(2).key])
        let reloaded = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try reloaded.load()
        #expect(reloaded.trustedClients() == [Self.phone(2).key])
    }

    @Test func testCorruptTrustedListThrowsAndIsNotReplaced() throws {
        let storage = InMemoryLinkSecretStorage()
        let garbage = Data("not json".utf8)
        storage.set(garbage, account: "trusted-clients.acct")
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")

        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.trust(Self.phone(1)) }
        #expect(throws: (any Error).self) { try store.untrust(key: Self.phone(1).key) }
        #expect(throws: (any Error).self) { try store.retainOnly(keys: []) }
        #expect(storage.raw("trusted-clients.acct") == garbage)
    }

    @Test func testCorruptHostKeyThrowsAndIsNotReplaced() throws {
        let storage = InMemoryLinkSecretStorage()
        storage.set(Data("short".utf8), account: "host-key.acct")
        #expect(throws: (any Error).self) { try ShellXLinkKeyStore(storage: storage, accountID: "acct").hostKey() }
        #expect(storage.raw("host-key.acct") == Data("short".utf8))
    }

    @Test func testRetainOnlyKeepsPhonesPairedSinceTheSnapshot() throws {
        let storage = InMemoryLinkSecretStorage()
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let snapshot = Date(timeIntervalSince1970: 1_800_000_100)
        let before = TrustedPhone(key: Data(repeating: 1, count: 32), deviceID: "d1", name: "Old",
                                  pairedAt: snapshot.addingTimeInterval(-10))
        let during = TrustedPhone(key: Data(repeating: 2, count: 32), deviceID: "d2", name: "New", pairedAt: snapshot)
        try store.trust(before)
        try store.trust(during)

        let removed = try store.retainOnly(keys: [], pairedSince: snapshot)

        #expect(removed == [before.key])
        #expect(store.trustedClients() == [during.key])
    }

    @Test func testUntrustDropsTheKeyEvenWhenSavingFails() throws {
        let storage = InMemoryLinkSecretStorage()
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try store.trust(Self.phone(1))
        try store.trust(Self.phone(2))
        storage.setWriteFailure(true)

        #expect(throws: (any Error).self) { try store.untrust(key: Self.phone(1).key) }

        #expect(store.trustedClients() == [Self.phone(2).key])
    }

    @Test func testRetainOnlyDropsKeysEvenWhenSavingFails() throws {
        let storage = InMemoryLinkSecretStorage()
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        try store.trust(Self.phone(1))
        storage.setWriteFailure(true)

        #expect(throws: (any Error).self) { try store.retainOnly(keys: []) }

        #expect(store.trustedClients().isEmpty)
    }

    // MARK: Development file store

    private struct RefusingKeychain: ShellXLinkSecretStorage {
        func read(account: String) throws -> Data? { throw ShellXLinkSecretError.unavailable(-34018) }
        func add(_ data: Data, account: String) throws -> Bool { throw ShellXLinkSecretError.unavailable(-34018) }
        func update(_ data: Data, account: String) throws { throw ShellXLinkSecretError.unavailable(-34018) }
    }

    private static func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-dev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func mode(_ url: URL) throws -> Int {
        ((try FileManager.default.attributesOfItem(atPath: url.path))[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func testMissingEntitlementInANonProductionBundleSelectsTheFileStore() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let notices = Box<Int>()
        let storage = FallbackLinkSecretStorage(
            primary: RefusingKeychain(),
            fallback: FallbackLinkSecretStorage.developmentFallback(bundleID: "pro.shellx.desktop.debug.link", home: home),
            onFallback: { notices.add(1) })
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")

        let key = try store.hostKey()
        try store.trust(Self.phone(1))
        _ = try store.hostKey()

        #expect(try ShellXLinkKeyStore(storage: storage, accountID: "acct").hostKey().publicKey == key.publicKey)
        #expect(notices.all.count == 1)   // logged once
        let directory = FileLinkSecretStorage.directory(home: home, bundleID: "pro.shellx.desktop.debug.link")
        #expect(try Self.mode(directory) == 0o700)
        #expect(try Self.mode(directory.appendingPathComponent("host-key.acct")) == 0o600)
        // Never the shared P1 directory.
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/ShellX/link").path))
    }

    @Test func testProductionNeverFallsBackToFiles() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(FallbackLinkSecretStorage.developmentFallback(bundleID: "pro.shellx.desktop", home: home) == nil)
        let storage = FallbackLinkSecretStorage(primary: RefusingKeychain(), fallback: nil)
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")

        #expect(throws: ShellXLinkSecretError.unavailable(-34018)) { try store.hostKey() }
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Library").path))
    }

    // MARK: Production Keychain (Developer ID, no provisioning profile)

    /// The release app is signed with Developer ID and no provisioning profile, so it has no keychain access
    /// group and the data-protection Keychain answers -34018. Its keys go to the login keychain, by a query
    /// that nothing routes back to the data-protection Keychain.
    @Test func testProductionKeepsLinkKeysInTheLoginKeychain() {
        let keychain = FallbackLinkSecretStorage.keychain(bundleID: shellXProductionBundleID)
        #expect(keychain.kind == .login)
        #expect(keychain.service == "pro.shellx.desktop.shellx-link")
        let insert = keychain.addQuery(Data([1]), account: "host-key.acct")
        #expect(insert[kSecUseDataProtectionKeychain as String] as? Bool == false)
        #expect(insert[kSecAttrAccessible as String] == nil)
        #expect(insert[kSecAttrAccessGroup as String] == nil)
    }

    @Test func testDevelopmentBuildsKeepTheDataProtectionKeychain() {
        let keychain = FallbackLinkSecretStorage.keychain(bundleID: "pro.shellx.desktop.debug.link")
        #expect(keychain.kind == .dataProtection)
        #expect(keychain.baseQuery("host-key.acct")[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    /// The real Keychain, from this test host: its signature carries no provisioning profile either, so the
    /// production storage must work here without `errSecMissingEntitlement`. Uses a throwaway service and
    /// deletes its item.
    @Test func testProductionKeychainNeedsNoKeychainEntitlement() throws {
        let kind = FallbackLinkSecretStorage.keychain(bundleID: shellXProductionBundleID).kind
        let storage = KeychainLinkSecretStorage(service: "pro.shellx.desktop.tests.\(UUID().uuidString).shellx-link",
                                                kind: kind)
        let account = "host-key.test"
        defer { SecItemDelete(storage.baseQuery(account) as CFDictionary) }
        do {
            #expect(try storage.read(account: account) == nil)
            #expect(try storage.add(Data("first".utf8), account: account))
            #expect(try storage.read(account: account) == Data("first".utf8))
            #expect(try !storage.add(Data("again".utf8), account: account))
            try storage.update(Data("second".utf8), account: account)
            #expect(try storage.read(account: account) == Data("second".utf8))
        } catch ShellXLinkSecretError.transient {
            // A locked login keychain (a headless runner): nothing can be checked, nothing was written.
        }
    }

    @MainActor
    @Test func testProductionHostStopsAsKeychainUnavailableWithoutRetry() async throws {
        let storage = FallbackLinkSecretStorage(primary: RefusingKeychain(), fallback: nil)
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let delays = Box<Duration>()

        await #expect(throws: ShellXLinkSecretError.unavailable(-34018)) {
            _ = try await ShellXLinkHostController.loadKeys(store, sleep: { delays.add($0) })
        }
        #expect(delays.all.isEmpty)
        #expect(ShellXLinkHostController.keyErrorKind(ShellXLinkSecretError.unavailable(-34018)) == "keychain_unavailable")
    }

    @Test func testFileStoreRoundTripsAndIsPerBundleID() throws {
        let home = try Self.temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let a = try #require(FallbackLinkSecretStorage.developmentFallback(bundleID: "pro.shellx.desktop.debug.a", home: home))
        let b = try #require(FallbackLinkSecretStorage.developmentFallback(bundleID: "pro.shellx.desktop.debug.b", home: home))

        #expect(try a.read(account: "host-key.x/../y") == nil)
        #expect(try a.add(Data("one".utf8), account: "host-key.x/../y"))
        #expect(try !a.add(Data("two".utf8), account: "host-key.x/../y"))
        #expect(try a.read(account: "host-key.x/../y") == Data("one".utf8))
        try a.update(Data("three".utf8), account: "host-key.x/../y")
        #expect(try a.read(account: "host-key.x/../y") == Data("three".utf8))
        #expect(try b.read(account: "host-key.x/../y") == nil)
        #expect(a.directory != b.directory)
        // One file per account name, no leftover temporary file.
        #expect(try FileManager.default.contentsOfDirectory(atPath: a.directory.path).count == 1)
    }

    @MainActor
    @Test func testTransientKeyErrorIsRetried() async throws {
        let storage = InMemoryLinkSecretStorage(readFailures: [.transient(-25308), .transient(-25308)])
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let delays = Box<Duration>()

        let key = try await ShellXLinkHostController.loadKeys(store, sleep: { delays.add($0) })

        #expect(key.publicKey.count == 32)
        #expect(delays.all == [.seconds(1), .seconds(2)])
    }

    // MARK: A locked login keychain

    /// A locked login keychain asks for its password. A cancelled prompt, a wrong password or no prompt allowed
    /// say nothing about the stored keys: they are transient, never `link_keys_corrupt`.
    @Test(arguments: [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed])
    func testLockedKeychainAnswersAreTransient(status: OSStatus) {
        #expect(KeychainLinkSecretStorage.secretError(for: status) == .transient(status))
    }

    @Test func testOtherKeychainFailuresKeepTheirKind() {
        #expect(KeychainLinkSecretStorage.secretError(for: errSecMissingEntitlement) == .unavailable(errSecMissingEntitlement))
        #expect(KeychainLinkSecretStorage.secretError(for: errSecDecode) == .failed(errSecDecode))
    }

    /// The person cancelled the keychain prompt: the host keeps its keys and tries again later, without asking
    /// again at once.
    @MainActor
    @Test func testCancelledKeychainPromptIsRetriedLater() async throws {
        let storage = InMemoryLinkSecretStorage(readFailures: [KeychainLinkSecretStorage.secretError(for: errSecUserCanceled)])
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let delays = Box<Duration>()

        let key = try await ShellXLinkHostController.loadKeys(store, sleep: { delays.add($0) })

        #expect(key.publicKey.count == 32)
        #expect(delays.all.count == 1)
        #expect(delays.all.allSatisfy { $0 >= .seconds(60) })
    }

    @MainActor
    @Test func testCorruptKeysStopWithoutRetry() async throws {
        let storage = InMemoryLinkSecretStorage()
        let garbage = Data("garbage".utf8)
        storage.set(garbage, account: "trusted-clients.acct")
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let delays = Box<Duration>()

        await #expect(throws: (any Error).self) {
            _ = try await ShellXLinkHostController.loadKeys(store, sleep: { delays.add($0) })
        }
        #expect(delays.all.isEmpty)
        #expect(storage.raw("trusted-clients.acct") == garbage)
    }
}

private final class Box<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []
    func add(_ value: Element) { lock.lock(); values.append(value); lock.unlock() }
    var all: [Element] { lock.lock(); defer { lock.unlock() }; return values }
}
