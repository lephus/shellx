import ShellXAppCore
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import ShellX

/// What a picked photo or file becomes before it goes with a message: its bytes as picked (nothing
/// scaled or re-encoded), a name, and a refusal past 10 MiB or when it cannot be read.
final class AttachmentPreparerTests: XCTestCase {
    private func temporaryFile(_ name: String, bytes: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-preparer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    private static func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - Photos

    func testPickedImageIsSentAsIs() throws {
        let png = Self.png(width: 4032, height: 3024)
        XCTAssertFalse(png.isEmpty)

        let attachment = try AttachmentPreparer.image(data: png, name: "photo-1.png")

        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(attachment.name, "photo-1.png")
        XCTAssertEqual(attachment.data, png, "the bytes the picker gave, not scaled or re-encoded")
    }

    func testImageOverTenMiBIsRefused() throws {
        let big = Data(count: ShellXLink.maxAttachmentBytes + 1)
        XCTAssertThrowsError(try AttachmentPreparer.image(data: big, name: "photo-1.jpg")) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .tooLarge(name: "photo-1.jpg"))
        }
        XCTAssertNoThrow(try AttachmentPreparer.image(data: Data(count: ShellXLink.maxAttachmentBytes), name: "ok.jpg"))
        XCTAssertThrowsError(try AttachmentPreparer.image(data: Data(), name: "photo-1.jpg")) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .unreadable(name: "photo-1.jpg"))
        }
    }

    func testPhotoIsNamedFromWhatItIs() throws {
        let png = Self.png(width: 8, height: 8)
        let jpeg = try XCTUnwrap(UIImage(data: png)?.jpegData(compressionQuality: 0.9))

        XCTAssertEqual(AttachmentPreparer.photoName(for: png, contentTypes: [.heic], taken: []), "photo-1.png")
        XCTAssertEqual(AttachmentPreparer.photoName(for: jpeg, contentTypes: [], taken: []), "photo-1.jpg")
        XCTAssertEqual(
            AttachmentPreparer.photoName(for: jpeg, contentTypes: [], taken: ["photo-1.jpg", "photo-2.jpg"]), "photo-3.jpg")
        // Bytes nothing can read: the item's own type, then JPEG.
        XCTAssertEqual(AttachmentPreparer.photoName(for: Data([1, 2, 3]), contentTypes: [.gif], taken: []), "photo-1.gif")
        XCTAssertEqual(AttachmentPreparer.photoName(for: Data(), contentTypes: [], taken: []), "photo-1.jpg")
    }

    // MARK: - Files

    func testFileIsReadWhole() throws {
        let url = try temporaryFile("build.log", bytes: 0)
        let text = Data("error: missing import\n".utf8)
        try text.write(to: url)

        let attachment = try AttachmentPreparer.file(at: url)

        XCTAssertEqual(attachment.kind, .file)
        XCTAssertEqual(attachment.name, "build.log")
        XCTAssertEqual(attachment.data, text)
    }

    func testFileOverTenMiBIsRefused() throws {
        let big = try temporaryFile("video.mov", bytes: ShellXLink.maxAttachmentBytes + 1)
        XCTAssertThrowsError(try AttachmentPreparer.file(at: big)) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .tooLarge(name: "video.mov"))
        }
        let atLimit = try temporaryFile("ok.bin", bytes: ShellXLink.maxAttachmentBytes)
        XCTAssertEqual(try AttachmentPreparer.file(at: atLimit).data.count, ShellXLink.maxAttachmentBytes)
    }

    func testUnreadableFileIsRefused() throws {
        let empty = try temporaryFile("empty.txt", bytes: 0)
        XCTAssertThrowsError(try AttachmentPreparer.file(at: empty)) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .unreadable(name: "empty.txt"), "the Mac takes 1 byte or more")
        }
        let missing = empty.deletingLastPathComponent().appendingPathComponent("gone.txt")
        XCTAssertThrowsError(try AttachmentPreparer.file(at: missing)) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .unreadable(name: "gone.txt"))
        }
        let folder = empty.deletingLastPathComponent()
        XCTAssertThrowsError(try AttachmentPreparer.file(at: folder)) { error in
            XCTAssertEqual(error as? AttachmentPreparer.Failure, .unreadable(name: folder.lastPathComponent))
        }
    }

    func testEveryFailureSaysWhichAttachment() {
        let failures: [AttachmentPreparer.Failure] = [.tooLarge(name: "video.mov"), .unreadable(name: "video.mov")]
        let messages = failures.map(\.message)
        XCTAssertEqual(Set(messages).count, 2)
        for message in messages { XCTAssertTrue(message.contains("video.mov"), message) }
    }
}
