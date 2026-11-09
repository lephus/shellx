import Foundation
import ShellXAppCore

/// The demo's secrets, in memory only: nothing reaches the Keychain.
public final class DemoSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SecretItem: Data] = [:]

    public init() {}

    public func read(_ item: SecretItem) throws -> Data? { lock.withLock { items[item] } }
    public func write(_ data: Data, for item: SecretItem) throws { lock.withLock { items[item] = data } }
    public func delete(_ item: SecretItem) throws { lock.withLock { items[item] = nil } }
}
