import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Mac's ShellX Link host key and trusted phones survive a relaunch, owner-only.
struct ShellXLinkKeyStoreTests {
    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-keys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent("link", isDirectory: true)
    }

    private static func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func hostKeyIsCreatedOnceOwnerOnlyAndReloaded() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let first = try ShellXLinkKeyStore(directory: directory).hostKey()
        let again = try ShellXLinkKeyStore(directory: directory).hostKey()

        #expect(first.publicKey.count == 32)
        #expect(again.publicKey == first.publicKey)
        #expect(try Self.mode(directory.appendingPathComponent("host-key")) == 0o600)
        #expect(try Self.mode(directory) == 0o700)
        // The private temporary file the key was written through is gone.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["host-key"])
    }

    @Test func trustedClientsPersistAcrossInstances() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let phone = Data(repeating: 7, count: 32)

        let store = ShellXLinkKeyStore(directory: directory)
        #expect(store.trustedClients().isEmpty)
        try store.trust(phone)
        #expect(store.trustedClients() == [phone])

        let reloaded = ShellXLinkKeyStore(directory: directory)
        try reloaded.load()
        #expect(reloaded.trustedClients() == [phone])
        #expect(try Self.mode(directory.appendingPathComponent("trusted-clients.json")) == 0o600)
    }

    /// `debug_invite` can trust a phone before the link host's startup `load()` ran: the phones already on
    /// disk must survive that write.
    @Test func trustBeforeLoadKeepsPhonesAlreadyOnDisk() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let earlier = Data(repeating: 1, count: 32), later = Data(repeating: 2, count: 32)
        try ShellXLinkKeyStore(directory: directory).trust(earlier)

        try ShellXLinkKeyStore(directory: directory).trust(later)   // no load() first

        let reloaded = ShellXLinkKeyStore(directory: directory)
        try reloaded.load()
        #expect(reloaded.trustedClients() == [earlier, later])
    }

    /// First-time creation from several threads still yields one key.
    @Test func concurrentFirstHostKeyIsOneKey() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ShellXLinkKeyStore(directory: directory)
        let keys = KeyBox()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            if let key = try? store.hostKey() { keys.add(key.publicKey) }
        }

        #expect(keys.all.count == 16)
        #expect(Set(keys.all).count == 1)
        #expect(try ShellXLinkKeyStore(directory: directory).hostKey().publicKey == keys.all.first)
    }
}

private final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [Data] = []
    func add(_ key: Data) { lock.lock(); keys.append(key); lock.unlock() }
    var all: [Data] { lock.lock(); defer { lock.unlock() }; return keys }
}
