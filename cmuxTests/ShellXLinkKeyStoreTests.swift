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
}
