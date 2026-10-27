import Foundation

/// The three secrets the app keeps. The raw value is the Keychain account name.
public enum SecretItem: String, CaseIterable, Sendable {
    case session
    case phoneKey = "phone-key"
    case machines
}

public enum SecretStoreError: Error, Equatable, Sendable {
    /// The store cannot be read right now (the Keychain before the first unlock after a restart,
    /// `errSecInteractionNotAllowed`). The data is still there: do not treat it as missing.
    case unavailable(status: Int32)
    case failed(status: Int32)
}

/// Where secrets live: the Keychain in the app, memory in tests.
public protocol SecretStore: Sendable {
    func read(_ item: SecretItem) throws -> Data?
    func write(_ data: Data, for item: SecretItem) throws
    func delete(_ item: SecretItem) throws
}
