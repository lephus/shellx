import Foundation
import ImageIO
import ShellXAppCore
import UniformTypeIdentifiers

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

    /// A file from the Files picker, under security-scoped access, named as it is there. Its size is
    /// read first, so a file too big is refused without being read.
    static func file(at url: URL) throws -> OutgoingAttachment {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ShellXLink.maxAttachmentBytes {
            throw Failure.tooLarge(name: name)
        }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(name: name) }
        guard data.count <= ShellXLink.maxAttachmentBytes else { throw Failure.tooLarge(name: name) }
        guard !data.isEmpty else { throw Failure.unreadable(name: name) }
        return OutgoingAttachment(kind: .file, name: name, data: data)
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
