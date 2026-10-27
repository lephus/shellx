import Foundation
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

    init(readFailures: [ShellXLinkSecretError] = []) { self.readFailures = readFailures }

    func read(account: String) throws -> Data? {
        try lock.withLock {
            if !readFailures.isEmpty { throw readFailures.removeFirst() }
            return items[account]
        }
    }

    func add(_ data: Data, account: String) throws -> Bool {
        lock.withLock {
            if items[account] != nil { return false }
            items[account] = data
            return true
        }
    }

    func update(_ data: Data, account: String) throws {
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

    @MainActor
    @Test func testTransientKeyErrorIsRetried() async throws {
        let storage = InMemoryLinkSecretStorage(readFailures: [.transient(-25308), .transient(-25308)])
        let store = ShellXLinkKeyStore(storage: storage, accountID: "acct")
        let delays = Box<Duration>()

        let key = try await ShellXLinkHostController.loadKeys(store, sleep: { delays.add($0) })

        #expect(key.publicKey.count == 32)
        #expect(delays.all == [.seconds(1), .seconds(2)])
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
