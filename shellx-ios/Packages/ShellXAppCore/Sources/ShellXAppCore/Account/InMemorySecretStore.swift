// Debug builds only (swift test, the ShellXTests bundle, previews and the demo): the App Store build
// never contains it, and release/mobile/ios.sh refuses an ipa that does.
#if DEBUG
import Foundation

/// A `SecretStore` in memory, for tests and previews. Each operation can be made to fail.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SecretItem: Data] = [:]
    private var writes: [SecretItem: Int] = [:]
    private var readFailure: SecretStoreError?
    private var writeFailure: SecretStoreError?
    private var deleteFailure: SecretStoreError?

    public init() {}

    public var failReads: SecretStoreError? {
        get { locked { readFailure } }
        set { locked { readFailure = newValue } }
    }

    public var failWrites: SecretStoreError? {
        get { locked { writeFailure } }
        set { locked { writeFailure = newValue } }
    }

    public var failDeletes: SecretStoreError? {
        get { locked { deleteFailure } }
        set { locked { deleteFailure = newValue } }
    }

    /// How many times `item` was written successfully.
    public func writeCount(for item: SecretItem) -> Int { locked { writes[item] ?? 0 } }

    public func read(_ item: SecretItem) throws -> Data? {
        try locked {
            if let readFailure { throw readFailure }
            return items[item]
        }
    }

    public func write(_ data: Data, for item: SecretItem) throws {
        try locked {
            if let writeFailure { throw writeFailure }
            items[item] = data
            writes[item, default: 0] += 1
        }
    }

    public func delete(_ item: SecretItem) throws {
        try locked {
            if let deleteFailure { throw deleteFailure }
            items[item] = nil
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
#endif
