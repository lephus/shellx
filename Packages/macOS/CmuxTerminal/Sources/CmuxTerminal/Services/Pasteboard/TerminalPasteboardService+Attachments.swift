public import Foundation

extension TerminalPasteboardService {
    /// The folder, inside the temporary directory, that holds one UUID folder per saved attachment file.
    static let attachmentsDirectoryName = "shellx-attachments"
    /// The longest stored attachment file name, in UTF-8 bytes of its canonically decomposed form (NFD), so a
    /// file system or Foundation version that stores names decomposed cannot grow it past 255 bytes.
    static let maxAttachmentFileNameBytes = 100
    /// The longest extension kept when a long attachment file name is cut.
    private static let maxKeptAttachmentExtensionBytes = 16

    /// Writes the bytes of a file a paired phone attached to a message to a private temporary file and returns
    /// its shell-escaped path, ready to type at an agent's prompt the way ``saveImageData(_:fileExtension:)``
    /// does for an image.
    ///
    /// The phone only suggests `fileName`; it never chooses where the file goes. The file lands in
    /// `<temporaryDirectory>/shellx-attachments/<UUID>/<name>` with a new UUID folder for every call (two
    /// attachments with one name never meet) and mode 0600. `<name>` is `fileName` without `/`, `\`, control
    /// characters and leading dots, cut to 100 UTF-8 bytes (counted decomposed) with its extension kept, and
    /// `file` when nothing is left, so it can neither leave its folder nor start a hidden file.
    ///
    /// Returns `nil` when the payload is empty, is over the 10 MB clipboard-image cap, or cannot be written
    /// (nothing is left behind then). The file and its folder are registered as owned, so the usual cleanup
    /// paths reclaim both. The name and the bytes are never logged.
    public func saveAttachmentData(_ data: Data, fileName: String) -> String? {
        guard !data.isEmpty, data.count <= Self.maxClipboardImageSize else { return nil }

        let attachmentsDirectory = temporaryDirectory
            .appendingPathComponent(Self.attachmentsDirectoryName, isDirectory: true)
        let folder = attachmentsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // The path is joined as text: a URL would re-normalize the name to decomposed form, which can grow a
        // 100-byte name (Hangul, for one) past the 255 bytes a file system takes in one component.
        let filePath = folder.path + "/" + sanitizedAttachmentFileName(fileName)

        let privateDirectory: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        do {
            try fileManager.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true,
                attributes: privateDirectory
            )
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: false,
                attributes: privateDirectory
            )
        } catch {
            return nil
        }
        guard fileManager.createFile(
            atPath: filePath,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? fileManager.removeItem(at: folder)
            return nil
        }
        registerOwnedTemporaryImageFile(URL(fileURLWithPath: filePath))
        registerOwnedTemporaryImageFile(folder)
        return filePath.terminalShellEscaped
    }

    /// A phone-suggested attachment file name as a single, visible path component of at most 100 UTF-8 bytes,
    /// decomposed or not: `/`, `\`, control characters and line or paragraph separators removed, then leading
    /// dots, then cut at a character boundary with a short extension kept; `file` when nothing is left.
    func sanitizedAttachmentFileName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                continue
            default:
                break
            }
            if scalar == "/" || scalar == "\\" { continue }
            scalars.append(scalar)
        }
        let visible = String(String.UnicodeScalarView(scalars.drop(while: { $0 == "." })))
        guard !visible.isEmpty else { return "file" }
        return Self.attachmentFileName(visible, cutToBytes: Self.maxAttachmentFileNameBytes)
    }

    /// `name` cut at a character boundary so that its decomposed form is at most `limit` UTF-8 bytes. A short
    /// extension survives the cut, so an agent can still tell what a long-named file is; the stem is never left
    /// empty. The precomposed form, never longer, fits as well.
    private static func attachmentFileName(_ name: String, cutToBytes limit: Int) -> String {
        guard decomposedByteCount(name) > limit else { return name }

        var stem = name
        var fileExtension = ""
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let suffix = String(name[dot...])
            if decomposedByteCount(suffix) <= Self.maxKeptAttachmentExtensionBytes {
                stem = String(name[..<dot])
                fileExtension = suffix
            }
        }

        let budget = limit - decomposedByteCount(fileExtension)
        var cutStem = ""
        var used = 0
        for character in stem {
            // Decomposition maps each character on its own, so the sizes add up to the whole name's.
            let size = decomposedByteCount(String(character))
            if used + size > budget { break }
            cutStem.append(character)
            used += size
        }
        return (cutStem.isEmpty ? "file" : cutStem) + fileExtension
    }

    /// The UTF-8 size of `text` once canonically decomposed (NFD): "한" is 3 bytes as typed and 9 decomposed.
    private static func decomposedByteCount(_ text: String) -> Int {
        text.decomposedStringWithCanonicalMapping.utf8.count
    }
}
