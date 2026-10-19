import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum OwnerOnlyFileError: Error, Equatable, Sendable {
    case insecureDirectory(path: String, reason: String)
    case insecureFile(path: String, reason: String)
    case io(operation: String, path: String, errno: Int32)
    case tooLarge(path: String)
    case invalidName(path: String)
}

/// Owner-only files with the same rules as shellx-core's state store (`shellx-core/src/store.rs`):
///
/// * The parent directory is opened `O_DIRECTORY|O_NOFOLLOW` and must be a directory owned by
///   `geteuid()` with no `0o077` bit (`0700`); every later step goes through that fd (`openat`/`renameat`).
/// * Writes go to an unpredictable temp name created `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC` mode `0600`,
///   then `fchmod 0600` (umask-proof), written, `fsync`ed, `renameat`ed over the target in the same
///   directory, and the directory is `fsync`ed. A symlink or non-regular target is refused.
/// * Reads open `O_NOFOLLOW|O_NONBLOCK` and check type, owner and mode on the opened fd.
/// * Errors carry paths and reasons only, never file bytes.
public enum OwnerOnlyFile {
    public static let maxBytes = 1 << 20

    public static func write(_ data: Data, to url: URL) throws {
        let (dirPath, name) = try split(url)
        let dfd = try openPrivateDirectory(dirPath)
        defer { close(dfd) }

        var st = stat()
        if fstatat(dfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 {
            if st.st_mode & S_IFMT != S_IFREG {
                throw OwnerOnlyFileError.insecureFile(path: url.path, reason: "is a symlink or not a regular file")
            }
        } else if errno != ENOENT {
            throw OwnerOnlyFileError.io(operation: "stat", path: url.path, errno: errno)
        }

        let tmp = ".\(name).tmp.\(randomHex())"
        let fd = openat(dfd, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw OwnerOnlyFileError.io(operation: "create temp", path: url.path, errno: errno) }
        var fdOpen = true
        var renamed = false
        defer {
            if fdOpen { close(fd) }
            if !renamed { unlinkat(dfd, tmp, 0) }
        }
        guard fchmod(fd, mode_t(0o600)) == 0 else {
            throw OwnerOnlyFileError.io(operation: "fchmod", path: url.path, errno: errno)
        }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = sysWrite(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw OwnerOnlyFileError.io(operation: "write", path: url.path, errno: errno)
                }
                offset += n
            }
        }
        guard fsync(fd) == 0 else { throw OwnerOnlyFileError.io(operation: "fsync", path: url.path, errno: errno) }
        close(fd); fdOpen = false
        guard renameat(dfd, tmp, dfd, name) == 0 else {
            throw OwnerOnlyFileError.io(operation: "rename", path: url.path, errno: errno)
        }
        renamed = true
        guard fsync(dfd) == 0 else { throw OwnerOnlyFileError.io(operation: "fsync dir", path: url.path, errno: errno) }
    }

    /// The file's bytes, or `nil` when it (or its directory) does not exist.
    public static func read(_ url: URL) throws -> Data? {
        let (dirPath, name) = try split(url)
        let dfd: Int32
        do { dfd = try openPrivateDirectory(dirPath) }
        catch OwnerOnlyFileError.io(_, _, let code) where code == ENOENT { return nil }
        defer { close(dfd) }

        let fd = openat(dfd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 {
            switch errno {
            case ENOENT: return nil
            case ELOOP: throw OwnerOnlyFileError.insecureFile(path: url.path, reason: "is a symlink")
            default: throw OwnerOnlyFileError.io(operation: "open", path: url.path, errno: errno)
            }
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw OwnerOnlyFileError.io(operation: "fstat", path: url.path, errno: errno) }
        guard st.st_mode & S_IFMT == S_IFREG else {
            throw OwnerOnlyFileError.insecureFile(path: url.path, reason: "not a regular file")
        }
        guard st.st_uid == geteuid() else {
            throw OwnerOnlyFileError.insecureFile(path: url.path, reason: "not owned by the current user")
        }
        guard st.st_mode & 0o077 == 0 else {
            throw OwnerOnlyFileError.insecureFile(path: url.path, reason: "group/other permissions set (need 0600)")
        }
        guard st.st_size <= maxBytes else { throw OwnerOnlyFileError.tooLarge(path: url.path) }
        var bytes = [UInt8](repeating: 0, count: Int(st.st_size))
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeMutableBytes { sysRead(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if n < 0 {
                if errno == EINTR { continue }
                throw OwnerOnlyFileError.io(operation: "read", path: url.path, errno: errno)
            }
            if n == 0 { break }
            offset += n
        }
        return Data(bytes[0..<offset])
    }

    /// Creates `url` (and missing parents) `0700`. The final component must be a real directory owned
    /// by `geteuid()`; one of ours with looser bits is tightened to `0700` through its fd.
    public static func ensurePrivateDirectory(_ url: URL) throws {
        let path = url.path
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            switch errno {
            case ELOOP, ENOTDIR: throw OwnerOnlyFileError.insecureDirectory(path: path, reason: "is a symlink or not a directory")
            default: throw OwnerOnlyFileError.io(operation: "open dir", path: path, errno: errno)
            }
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw OwnerOnlyFileError.io(operation: "fstat dir", path: path, errno: errno) }
        guard st.st_mode & S_IFMT == S_IFDIR else {
            throw OwnerOnlyFileError.insecureDirectory(path: path, reason: "not a directory")
        }
        guard st.st_uid == geteuid() else {
            throw OwnerOnlyFileError.insecureDirectory(path: path, reason: "not owned by the current user")
        }
        if st.st_mode & 0o777 != 0o700, fchmod(fd, mode_t(0o700)) != 0 {
            throw OwnerOnlyFileError.io(operation: "fchmod dir", path: path, errno: errno)
        }
    }

    // MARK: - Helpers

    private static func split(_ url: URL) throws -> (dir: String, name: String) {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/", !name.contains("/") else {
            throw OwnerOnlyFileError.invalidName(path: url.path)
        }
        return (url.deletingLastPathComponent().path, name)
    }

    /// Opens the directory itself without following a symlink and checks owner and `0o077` bits on the fd.
    private static func openPrivateDirectory(_ path: String) throws -> Int32 {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            switch errno {
            case ELOOP, ENOTDIR: throw OwnerOnlyFileError.insecureDirectory(path: path, reason: "is a symlink or not a directory")
            default: throw OwnerOnlyFileError.io(operation: "open dir", path: path, errno: errno)
            }
        }
        var st = stat()
        let reason: String?
        if fstat(fd, &st) != 0 { reason = "cannot stat" }
        else if st.st_mode & S_IFMT != S_IFDIR { reason = "not a directory" }
        else if st.st_uid != geteuid() { reason = "not owned by the current user" }
        else if st.st_mode & 0o077 != 0 { reason = "group/other permissions set (need 0700)" }
        else { reason = nil }
        if let reason {
            close(fd)
            throw OwnerOnlyFileError.insecureDirectory(path: path, reason: reason)
        }
        return fd
    }

    private static func sysWrite(_ fd: Int32, _ buf: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buf, count)
        #else
        Glibc.write(fd, buf, count)
        #endif
    }

    private static func sysRead(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(fd, buf, count)
        #else
        Glibc.read(fd, buf, count)
        #endif
    }

    private static func randomHex() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<2).map { _ in String(generator.next() as UInt64, radix: 16) }.joined()
    }
}
