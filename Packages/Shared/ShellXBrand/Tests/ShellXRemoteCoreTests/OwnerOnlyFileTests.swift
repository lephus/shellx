import Foundation
import Testing
@testable import ShellXRemoteCore

private func privateDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sx-own-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return dir
}

private func mode(_ url: URL) throws -> Int {
    try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

@Test func ownerOnlyWriteIs0600AndAtomic() throws {
    let dir = try privateDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("links.json")
    #expect(try OwnerOnlyFile.read(file) == nil)
    try OwnerOnlyFile.write(Data("one".utf8), to: file)
    #expect(try mode(file) == 0o600)
    #expect(try OwnerOnlyFile.read(file) == Data("one".utf8))
    // Overwrite replaces the file by rename (new inode) and leaves no temp files behind.
    let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
    try OwnerOnlyFile.write(Data("two".utf8), to: file)
    #expect(try OwnerOnlyFile.read(file) == Data("two".utf8))
    #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int != inode)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["links.json"])
    #expect(try mode(file) == 0o600)
}

@Test func refusesSymlinkTarget() throws {
    let dir = try privateDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let real = dir.appendingPathComponent("real")
    try OwnerOnlyFile.write(Data("secret".utf8), to: real)
    let link = dir.appendingPathComponent("links.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.read(link) }
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.write(Data("x".utf8), to: link) }
    #expect(try OwnerOnlyFile.read(real) == Data("secret".utf8))
    // A symlinked parent directory is refused too.
    let linkedDir = dir.appendingPathComponent("linked-dir")
    let inner = dir.appendingPathComponent("inner", isDirectory: true)
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try FileManager.default.createSymbolicLink(at: linkedDir, withDestinationURL: inner)
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.write(Data("x".utf8), to: linkedDir.appendingPathComponent("f")) }
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.ensurePrivateDirectory(linkedDir) }
}

@Test func refusesGroupReadableFile() throws {
    let dir = try privateDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("links.json")
    try OwnerOnlyFile.write(Data("x".utf8), to: file)
    #expect(chmod(file.path, 0o640) == 0)
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.read(file) }
    #expect(chmod(file.path, 0o604) == 0)
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.read(file) }
}

@Test func refusesLooseParentDirectory() throws {
    let dir = try privateDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("links.json")
    try OwnerOnlyFile.write(Data("x".utf8), to: file)
    #expect(chmod(dir.path, 0o755) == 0)
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.write(Data("y".utf8), to: file) }
    #expect(throws: OwnerOnlyFileError.self) { try OwnerOnlyFile.read(file) }
    // ensurePrivateDirectory tightens a directory we own back to 0700.
    try OwnerOnlyFile.ensurePrivateDirectory(dir)
    #expect(try mode(dir) == 0o700)
    #expect(try OwnerOnlyFile.read(file) == Data("x".utf8))
    let nested = dir.appendingPathComponent("a/b", isDirectory: true)
    try OwnerOnlyFile.ensurePrivateDirectory(nested)
    #expect(try mode(nested) == 0o700)
}

@Test func linkStoreRoundTrip() throws {
    let dir = try privateDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let paths = RemotePaths(bundleID: "pro.shellx.desktop", home: dir, temporaryDirectory: dir)
    let store = RemoteLinkStore(paths: paths)
    #expect(store.file == paths.stateRoot.appendingPathComponent("links.json"))
    #expect(try store.load() == [])
    let a = RemoteLinkRecord(machineID: "m_1", route: "relay+wss://r/v2/relay", slot: "S1", daemonFingerprint: "aa", enrolled: false)
    let b = RemoteLinkRecord(machineID: "m_2", route: "relay+wss://r/v2/relay", slot: "S2", daemonFingerprint: "bb", enrolled: true)
    try store.save([a, b])
    #expect(try store.load() == [a, b])
    #expect(try mode(store.file) == 0o600)
    #expect(try mode(paths.stateRoot) == 0o700)
    var a2 = a; a2.enrolled = true
    try store.upsert(a2)
    #expect(try store.load() == [a2, b])
    let c = RemoteLinkRecord(machineID: "m_3", route: "relay+wss://r/v2/relay", slot: "S3", daemonFingerprint: "cc", enrolled: false)
    try store.upsert(c)
    #expect(try store.load() == [a2, b, c])
}
