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

    /// Files are read through `NSFileCoordinator` (which downloads an iCloud Drive item first; that
    /// part cannot run in a test): a plain file in a folder with spaces reads the same.
    func testCoordinatedReadOfAPlainFile() throws {
        let url = try temporaryFile("Báo cáo lỗi (1).txt", bytes: 0)
        let text = Data(String(repeating: "dòng lỗi\n", count: 2_000).utf8)
        try text.write(to: url)

        let attachment = try AttachmentPreparer.file(at: url)

        XCTAssertEqual(attachment.name, "Báo cáo lỗi (1).txt")
        XCTAssertEqual(attachment.data, text)
    }

    /// The composer reads a picked file off the main actor through `readFile(at:)`: the same bytes.
    func testAPickedFileIsReadOffTheMainActor() async throws {
        let url = try temporaryFile("notes.md", bytes: 0)
        let text = Data("# notes\n".utf8)
        try text.write(to: url)

        let attachment = try await AttachmentPreparer.readFile(at: url)

        XCTAssertEqual(attachment.name, "notes.md")
        XCTAssertEqual(attachment.data, text)
    }

    /// Finding I3: a coordinated read that never gets its file (an iCloud item that does not
    /// download; here a file presenter that keeps the file) stops when its pick is cancelled,
    /// instead of holding the composer for good.
    func testCancellingAHungFileReadStopsIt() async throws {
        let url = try temporaryFile("held.txt", bytes: 4)
        let presenter = HoldingPresenter(url)
        NSFileCoordinator.addFilePresenter(presenter)
        defer {
            NSFileCoordinator.removeFilePresenter(presenter)
            presenter.letGo()
        }

        let read = Task { try await AttachmentPreparer.readFile(at: url) }
        let ended = Flag()
        Task {
            _ = await read.result
            ended.set()
        }
        let held = await Self.eventually { presenter.wasAsked }
        XCTAssertTrue(held, "the read did not wait for the file presenter")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(ended.isSet, "the read did not wait")

        read.cancel()
        let stopped = await Self.eventually { ended.isSet }
        XCTAssertTrue(stopped, "the cancelled read still waits for the file")
        // A read that did not stop goes on once the file is free, so this test never hangs.
        presenter.letGo()
        let result = await read.result
        XCTAssertThrowsError(try result.get(), "a cancelled read reads nothing")
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

    private static func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testEveryFailureSaysWhichAttachment() {
        let failures: [AttachmentPreparer.Failure] = [.tooLarge(name: "video.mov"), .unreadable(name: "video.mov")]
        let messages = failures.map(\.message)
        XCTAssertEqual(Set(messages).count, 2)
        for message in messages { XCTAssertTrue(message.contains("video.mov"), message) }
    }
}

/// A file presenter that keeps its file from every reader until `letGo()`: a coordinated read of it
/// waits meanwhile.
private final class HoldingPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var reader: (@Sendable ((@Sendable () -> Void)?) -> Void)?
    private var asked = false

    init(_ url: URL) {
        presentedItemURL = url
    }

    var wasAsked: Bool { lock.withLock { asked } }

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        lock.withLock {
            self.reader = reader
            asked = true
        }
    }

    func letGo() {
        let reader = lock.withLock { () -> (@Sendable ((@Sendable () -> Void)?) -> Void)? in
            defer { self.reader = nil }
            return self.reader
        }
        reader?(nil)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
