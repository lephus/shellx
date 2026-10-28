import Foundation
import ImageIO
import ShellXAppCore
import UniformTypeIdentifiers
import os

/// Turns a picked photo or file into an `OutgoingAttachment`, as picked (ruling R9): a photo keeps
/// the bytes the photo picker delivered (it asks for `.compatible`, so iOS itself hands a HEIC photo
/// over as JPEG), a file is read whole. Nothing is scaled or re-encoded. Anything over
/// `ShellXLink.maxAttachmentBytes` is refused, and so is what cannot be read or is empty (the Mac
/// takes 1 byte to 10 MiB).
///
/// These functions read files and look into bytes: call them off the main actor.
enum AttachmentPreparer {
    enum Failure: Error, Equatable {
        case tooLarge(name: String)
        case unreadable(name: String)

        /// The red line under the composer.
        var message: String {
            switch self {
            case let .tooLarge(name): String(localized: "composer.attach.tooLarge \(name)")
            case let .unreadable(name): String(localized: "composer.attach.unreadable \(name)")
            }
        }
    }

    /// A photo's bytes, checked for size only.
    static func image(data: Data, name: String) throws -> OutgoingAttachment {
        guard data.count <= ShellXLink.maxAttachmentBytes else { throw Failure.tooLarge(name: name) }
        guard !data.isEmpty else { throw Failure.unreadable(name: name) }
        return OutgoingAttachment(kind: .image, name: name, data: data)
    }

    /// `file(at:)` off the main actor, as the composer reads a picked file. Cancelling the calling
    /// task cancels the coordinated read, so an iCloud download that stalls stops with the pick's ✕
    /// (the read then throws, and the composer has dropped the pick already).
    static func readFile(at url: URL) async throws -> OutgoingAttachment {
        let read = CancellableRead()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                if read.isCancelled { throw Failure.unreadable(name: url.lastPathComponent) }
                return try file(at: url, coordinator: read.coordinator)
            }.value
        } onCancel: {
            read.cancel()
        }
    }

    /// A file from the Files picker, named as it is there. It is read under security-scoped access,
    /// through `coordinator`, which first downloads an iCloud Drive item that is not on the iPhone
    /// yet (a plain read fails on it). Its size is checked before the read when the file system
    /// knows it, so a file too big is refused without being read, and again after.
    static func file(at url: URL, coordinator: NSFileCoordinator = NSFileCoordinator()) throws -> OutgoingAttachment {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = fileSize(url), size > ShellXLink.maxAttachmentBytes { throw Failure.tooLarge(name: name) }

        var coordinationError: NSError?
        var read: Result<Data, any Error> = .failure(Failure.unreadable(name: name))
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { local in
            // Downloaded now: its size may be known only here.
            if let size = fileSize(local), size > ShellXLink.maxAttachmentBytes {
                read = .failure(Failure.tooLarge(name: name))
                return
            }
            read = Result { try Data(contentsOf: local) }
        }
        let data: Data
        do {
            if let coordinationError { throw coordinationError }
            data = try read.get()
        } catch let failure as Failure {
            throw failure
        } catch {
            // The reason, never the name: a path can say more than the user meant to share.
            let reason = error as NSError
            log.notice("attach_file_unreadable domain=\(reason.domain, privacy: .public) code=\(reason.code)")
            throw Failure.unreadable(name: name)
        }
        guard data.count <= ShellXLink.maxAttachmentBytes else { throw Failure.tooLarge(name: name) }
        guard !data.isEmpty else { throw Failure.unreadable(name: name) }
        return OutgoingAttachment(kind: .file, name: name, data: data)
    }

    private static let log = Logger(subsystem: "com.shellx.app", category: "attachments")

    /// A coordinated read another task can stop: `NSFileCoordinator.cancel()` is meant to be called
    /// from another thread than the one that reads, and makes the read return at once with an error.
    private final class CancellableRead: @unchecked Sendable {
        let coordinator = NSFileCoordinator()
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }

        func cancel() {
            lock.withLock { cancelled = true }
            coordinator.cancel()
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// "photo-<n>.<extension>", with the first `n` from 1 that no name in `taken` has. The extension
    /// is that of the image type ImageIO finds in the bytes (what the picker delivered), else of the
    /// item's first image type, else "jpg".
    static func photoName(for data: Data, contentTypes: [UTType], taken: [String]) -> String {
        let fileExtension = photoExtension(for: data, contentTypes: contentTypes)
        let used = Set(taken)
        var number = 1
        while used.contains("photo-\(number).\(fileExtension)") { number += 1 }
        return "photo-\(number).\(fileExtension)"
    }

    private static func photoExtension(for data: Data, contentTypes: [UTType]) -> String {
        let found = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceGetType($0) }
            .flatMap { UTType($0 as String) }
        guard let type = found ?? contentTypes.first(where: { $0.conforms(to: .image) }) else { return "jpg" }
        if type.conforms(to: .jpeg) { return "jpg" }
        return type.preferredFilenameExtension ?? "jpg"
    }
}
