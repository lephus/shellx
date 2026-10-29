import CryptoKit
import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

/// Uploads inside one Link session (PROTOCOL.md section 5, "Attachments"): `LinkClient.uploadAttachment` on one
/// side, `LinkHost` and its `AttachmentUploads` on the other.
final class AttachmentSessionTests: XCTestCase {
    private var serveTasks: [Task<Void, Never>] = []
    private var clients: [LinkClient] = []

    override func tearDown() async throws {
        for client in clients { await client.close() }
        for task in serveTasks {
            task.cancel()
            await task.value
        }
        serveTasks = []
        clients = []
    }

    // MARK: - The whole path

    func testImageAndFileReachTheChatSourceWithTheText() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        XCTAssertEqual(client.hostFeatures, [ShellXLink.attachmentsFeature])

        let file = Data((0..<100_000).map { UInt8($0 % 251) })
        let photo = Data((0..<10).map { UInt8($0) })
        let progress = Collector<Int>()
        let fileId = try await within {
            try await client.uploadAttachment(kind: .file, name: "build.log", data: file) { progress.append($0) }
        }
        let photoId = try await within { try await client.uploadAttachment(kind: .image, name: "shot.jpg", data: photo) }
        XCTAssertNotEqual(fileId, photoId)
        // 100 000 bytes go in three chunks, and each result reports the bytes sent so far.
        XCTAssertEqual(progress.items, [45_000, 90_000, 100_000])

        let outcome = try await within {
            try await client.chatSend(sessionId: "s1", text: "fix this", attachments: [fileId, photoId])
        }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.count, 1)
        XCTAssertEqual(chat.attachmentSends.first?.sessionId, "s1")
        XCTAssertEqual(chat.attachmentSends.first?.text, "fix this")
        XCTAssertEqual(chat.attachmentSends.first?.attachments, [
            ChatAttachment(kind: .file, name: "build.log", data: file),
            ChatAttachment(kind: .image, name: "shot.jpg", data: photo),
        ])
        XCTAssertTrue(chat.sends.isEmpty, "a message with attachments is not also typed as plain text")
    }

    func testAttachmentsWithoutTextAreSent() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let id = try await within { try await client.uploadAttachment(kind: .image, name: "a.jpg", data: Data([1, 2, 3])) }
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.text, "")
        XCTAssertEqual(chat.attachmentSends.first?.attachments.count, 1)
    }

    func testTextAloneStillTakesTheTextPath() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "hello") }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.sends.map(\.text), ["hello"])
        XCTAssertTrue(chat.attachmentSends.isEmpty)
        // Without attachments the text must still be 1 to 16 384 bytes.
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "") }
    }

    /// The frames themselves: ids, `received` and the call_id of every answer.
    func testRawUploadFlow() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig, features: ["attachments"])
        let bytes = Data((0..<7).map { UInt8($0) })

        try await raw.send(.attachBegin(callId: "b1", kind: .image, name: "a.jpg", size: 7))
        let ready = try await within { try await raw.receive() }
        guard case let .attachReady("b1", id) = ready else { return XCTFail("expected attach.ready, got \(ready)") }
        XCTAssertTrue((1...64).contains(id.utf8.count))
        try await raw.send(.attachChunk(callId: "k1", attachmentId: id, offset: 0, data: bytes.prefix(3)))
        let first = try await within { try await raw.receive() }
        XCTAssertEqual(first, .attachChunkResult(callId: "k1", attachmentId: id, received: 3))
        try await raw.send(.attachChunk(callId: "k2", attachmentId: id, offset: 3, data: bytes.suffix(4)))
        let second = try await within { try await raw.receive() }
        XCTAssertEqual(second, .attachChunkResult(callId: "k2", attachmentId: id, received: 7))
        try await raw.send(.attachEnd(callId: "e1", attachmentId: id, sha256: digest(bytes)))
        let ended = try await within { try await raw.receive() }
        XCTAssertEqual(ended, .attachEndResult(callId: "e1", attachmentId: id))

        try await raw.send(.chatSend(callId: "m1", sessionId: "s1", text: "look", attachments: [id]))
        let sent = try await within { try await raw.receive() }
        XCTAssertEqual(sent, .chatSendResult(callId: "m1", outcome: .submitted))
        XCTAssertEqual(chat.attachmentSends.first?.attachments, [ChatAttachment(kind: .image, name: "a.jpg", data: bytes)])
        XCTAssertFalse(served.isSet)
    }

    // MARK: - begin

    func testOversizeIsRefusedAtBegin() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        // The client sends `attach.begin` first, so the 10 MiB + 1 byte never go over the wire.
        let tooBig = Data(count: ShellXLink.maxAttachmentBytes + 1)
        await expectRemote("too_large") {
            try await client.uploadAttachment(kind: .file, name: "big.bin", data: tooBig)
        }
        // A size below 1 is a bad request, and nothing was stored by either refusal.
        await expectRemote("bad_request") { try await client.uploadAttachment(kind: .file, name: "none", data: Data()) }
        // The limit itself is fine (only the begin: the bytes are not sent).
        let ready = try await within {
            try await client.call { .attachBegin(callId: $0, kind: .file, name: "max.bin", size: ShellXLink.maxAttachmentBytes) }
        }
        guard case .attachReady = ready else { return XCTFail("expected attach.ready, got \(ready)") }
    }

    func testAnUnknownKindIsRefusedAtBegin() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        await expectRemote("bad_request") {
            try await client.uploadAttachment(kind: .other("video"), name: "clip.mov", data: Data([1]))
        }
    }

    /// At the cap of 5 unsent uploads, a new upload drops the one that finished first instead of being refused.
    func testASixthUploadDropsTheOldestUnsentOne() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        var ids: [String] = []
        for number in 0...ShellXLink.maxPendingUploads {
            let bytes = Data([UInt8(number)])
            ids.append(try await within { try await client.uploadAttachment(kind: .file, name: "f\(number)", data: bytes) })
        }

        let oldest = ids[0]
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "", attachments: [oldest]) }
        let rest = Array(ids.dropFirst())
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "go", attachments: rest) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["f1", "f2", "f3", "f4", "f5"])
    }

    /// Finding I1: a message whose send failed after three of its uploads finished is sent again whole. Those three
    /// still hold places, and the retry's five uploads must not be refused for them.
    func testARetryAfterAFailedAttemptIsNotRefused() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        for number in 0..<3 {
            let bytes = Data([UInt8(number)])
            _ = try await within { try await client.uploadAttachment(kind: .file, name: "old\(number)", data: bytes) }
        }

        var ids: [String] = []
        for number in 0..<ShellXLink.maxAttachmentsPerMessage {
            let bytes = Data([UInt8(10 + number)])
            ids.append(try await within { try await client.uploadAttachment(kind: .file, name: "new\(number)", data: bytes) })
        }
        let retry = ids
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "again", attachments: retry) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["new0", "new1", "new2", "new3", "new4"])
    }

    // MARK: - Abandoned and stale uploads

    func testBeginDropsAnUnfinishedUpload() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        // An upload given up after its first chunk.
        let abandoned = try await within {
            try await client.call { .attachBegin(callId: $0, kind: .file, name: "old", size: 3) }
        }
        guard case let .attachReady(_, oldId) = abandoned else { return XCTFail("expected attach.ready") }
        _ = try await within {
            try await client.call { .attachChunk(callId: $0, attachmentId: oldId, offset: 0, data: Data([1, 2])) }
        }

        // The next upload starts and finishes.
        let newId = try await within { try await client.uploadAttachment(kind: .file, name: "new", data: Data([9])) }

        // The old one is gone: no chunk completes it, and no message can name it.
        await expectRemote("bad_request") {
            try await client.call { .attachChunk(callId: $0, attachmentId: oldId, offset: 2, data: Data([3])) }
        }
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: [oldId]) }
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [newId]) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["new"])
    }

    func testFiveAbandonedUploadsDoNotBlockTheSixth() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        // Six begins and no end: each one drops the one before, so none is refused.
        var last = ""
        for number in 0...ShellXLink.maxPendingUploads {
            let answer = try await within {
                try await client.call { .attachBegin(callId: $0, kind: .file, name: "f\(number)", size: 4) }
            }
            guard case let .attachReady(_, id) = answer else { return XCTFail("begin \(number) got \(answer)") }
            last = id
        }
        XCTAssertFalse(last.isEmpty)
        // And a whole upload still goes through afterwards.
        let id = try await within { try await client.uploadAttachment(kind: .file, name: "ok", data: Data([1])) }
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
        XCTAssertEqual(outcome, .submitted)
    }

    func testEndedUploadExpiresAfterFiveMinutes() async throws {
        let clock = UploadTestClock()
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat, clock: clock))
        let early = try await within { try await client.uploadAttachment(kind: .file, name: "early", data: Data([1])) }
        let late = try await within { try await client.uploadAttachment(kind: .file, name: "late", data: Data([2])) }

        clock.advance(.seconds(299))
        let used = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [early]) }
        XCTAssertEqual(used, .submitted, "4 min 59 s after its end an upload can still be named")
        clock.advance(.seconds(2))
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "", attachments: [late]) }
        XCTAssertEqual(chat.attachmentSends.map { $0.attachments.map(\.name) }, [["early"]])
    }

    /// Finding I2: a slow message uploads its attachments minutes apart. The first one must still be there when the
    /// last one is up and the message names them all.
    func testUploadsMinutesApartAreSentTogether() async throws {
        let clock = UploadTestClock()
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat, clock: clock))
        let first = try await within { try await client.uploadAttachment(kind: .file, name: "first", data: Data([1])) }
        clock.advance(.seconds(240))
        let second = try await within { try await client.uploadAttachment(kind: .file, name: "second", data: Data([2])) }
        clock.advance(.seconds(240))

        let outcome = try await within {
            try await client.chatSend(sessionId: "s1", text: "both", attachments: [first, second])
        }
        XCTAssertEqual(outcome, .submitted, "8 min after the first upload ended, 4 min after the last upload call")
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["first", "second"])
    }

    /// Every accepted `attach.*` call, a chunk or an end as much as a begin, keeps the session's uploads alive.
    func testTheLifetimeCountsFromTheLastAcceptedUploadCall() async throws {
        let clock = UploadTestClock()
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat, clock: clock))
        let early = try await within { try await client.uploadAttachment(kind: .file, name: "early", data: Data([9])) }
        clock.advance(.seconds(200))
        let begun = try await within {
            try await client.call { .attachBegin(callId: $0, kind: .file, name: "slow", size: 2) }
        }
        guard case let .attachReady(_, slow) = begun else { return XCTFail("expected attach.ready") }
        clock.advance(.seconds(200))
        let bytes = Data([1, 2])
        _ = try await within {
            try await client.call { .attachChunk(callId: $0, attachmentId: slow, offset: 0, data: bytes) }
        }
        clock.advance(.seconds(200))
        let sha = digest(bytes)
        _ = try await within { try await client.call { .attachEnd(callId: $0, attachmentId: slow, sha256: sha) } }
        clock.advance(.seconds(50))

        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [early, slow]) }
        XCTAssertEqual(outcome, .submitted)
    }

    /// A call the host refused is not activity: it does not keep the uploads alive.
    func testARefusedCallDoesNotKeepUploadsAlive() async throws {
        let clock = UploadTestClock()
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat, clock: clock))
        let id = try await within { try await client.uploadAttachment(kind: .file, name: "a", data: Data([1])) }
        clock.advance(.seconds(200))
        await expectRemote("bad_request") {
            try await client.call { .attachChunk(callId: $0, attachmentId: "nope", offset: 0, data: Data([1])) }
        }
        clock.advance(.seconds(200))
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
    }

    /// Five minutes with no accepted upload call drop every unsent upload, which then holds no place.
    func testAnIdleSessionDropsEveryUnsentUpload() async throws {
        let clock = UploadTestClock()
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat, clock: clock))
        var ids: [String] = []
        for number in 0..<ShellXLink.maxPendingUploads {
            let bytes = Data([UInt8(number)])
            ids.append(try await within { try await client.uploadAttachment(kind: .file, name: "f\(number)", data: bytes) })
        }
        clock.advance(.seconds(301))
        let fresh = try await within { try await client.uploadAttachment(kind: .file, name: "f5", data: Data([5])) }
        for id in ids {
            await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
        }
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [fresh]) }
        XCTAssertEqual(outcome, .submitted)
    }

    // MARK: - chunks

    func testOutOfOrderChunkIsRefused() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig, features: ["attachments"])
        let id = try await begin(raw, size: 10)

        // The offset must equal the bytes held: here 0.
        try await raw.send(.attachChunk(callId: "k1", attachmentId: id, offset: 5, data: Data([1, 2])))
        try await expectError(raw, "bad_request", callId: "k1")
        // That chunk was not applied: offset 0 is still the next one.
        try await raw.send(.attachChunk(callId: "k2", attachmentId: id, offset: 0, data: Data([1, 2, 3])))
        let applied = try await within { try await raw.receive() }
        XCTAssertEqual(applied, .attachChunkResult(callId: "k2", attachmentId: id, received: 3))
        // A repeat of an applied chunk is out of order too.
        try await raw.send(.attachChunk(callId: "k3", attachmentId: id, offset: 0, data: Data([1, 2, 3])))
        try await expectError(raw, "bad_request", callId: "k3")
        // And one that would pass `size` (3 + 8 > 10) is refused whole.
        try await raw.send(.attachChunk(callId: "k4", attachmentId: id, offset: 3, data: Data(count: 8)))
        try await expectError(raw, "bad_request", callId: "k4")
        // An empty chunk, a chunk for an id the host does not hold: bad_request.
        try await raw.send(.attachChunk(callId: "k5", attachmentId: id, offset: 3, data: Data()))
        try await expectError(raw, "bad_request", callId: "k5")
        try await raw.send(.attachChunk(callId: "k6", attachmentId: "nope", offset: 0, data: Data([1])))
        try await expectError(raw, "bad_request", callId: "k6")
        XCTAssertFalse(served.isSet)
    }

    func testAChunkOfMoreThanTheLimitIsRefused() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let (end, _) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig, features: ["attachments"])
        let id = try await begin(raw, size: 60_000)
        try await raw.send(.attachChunk(
            callId: "k1", attachmentId: id, offset: 0, data: Data(count: ShellXLink.maxAttachmentChunkBytes + 1)))
        try await expectError(raw, "bad_request", callId: "k1")
        try await raw.send(.attachChunk(
            callId: "k2", attachmentId: id, offset: 0, data: Data(count: ShellXLink.maxAttachmentChunkBytes)))
        let applied = try await within { try await raw.receive() }
        XCTAssertEqual(
            applied, .attachChunkResult(callId: "k2", attachmentId: id, received: ShellXLink.maxAttachmentChunkBytes))
    }

    // MARK: - end

    func testWrongDigestDropsTheUpload() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let (end, served) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig, features: ["attachments"])
        let bytes = Data([1, 2, 3])
        let id = try await begin(raw, size: 3)
        try await raw.send(.attachChunk(callId: "k1", attachmentId: id, offset: 0, data: bytes))
        _ = try await within { try await raw.receive() }

        try await raw.send(.attachEnd(callId: "e1", attachmentId: id, sha256: digest(Data([9, 9, 9]))))
        try await expectError(raw, "bad_request", callId: "e1")
        // The upload is gone: it cannot be ended again, added to, or sent.
        try await raw.send(.attachEnd(callId: "e2", attachmentId: id, sha256: digest(bytes)))
        try await expectError(raw, "bad_request", callId: "e2")
        try await raw.send(.chatSend(callId: "m1", sessionId: "s1", text: "see", attachments: [id]))
        try await expectError(raw, "bad_request", callId: "m1")
        XCTAssertTrue(chat.sends.isEmpty && chat.attachmentSends.isEmpty, "nothing was typed")
        XCTAssertFalse(served.isSet)
    }

    func testEndBeforeAllBytesDropsTheUpload() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let (end, _) = startServe(rig.host)
        let raw = try await rawEstablished(end, rig, features: ["attachments"])
        let bytes = Data([1, 2])
        let id = try await begin(raw, size: 3)
        try await raw.send(.attachChunk(callId: "k1", attachmentId: id, offset: 0, data: bytes))
        _ = try await within { try await raw.receive() }
        // The digest is right for the 2 bytes held, but 3 were announced.
        try await raw.send(.attachEnd(callId: "e1", attachmentId: id, sha256: digest(bytes)))
        try await expectError(raw, "bad_request", callId: "e1")
        try await raw.send(.attachChunk(callId: "k2", attachmentId: id, offset: 2, data: Data([3])))
        try await expectError(raw, "bad_request", callId: "k2")
    }

    func testAFinishedUploadCannotBeEndedTwiceButStaysUsable() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let bytes = Data([4, 5])
        let id = try await within { try await client.uploadAttachment(kind: .file, name: "a", data: bytes) }
        let again = digest(bytes)
        await expectRemote("bad_request") {
            try await client.call { .attachEnd(callId: $0, attachmentId: id, sha256: again) }
        }
        await expectRemote("bad_request") {
            try await client.call { .attachChunk(callId: $0, attachmentId: id, offset: 2, data: Data([6])) }
        }
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.first?.data, bytes)
    }

    // MARK: - chat.send

    func testUploadIsUsedOnce() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let id = try await within { try await client.uploadAttachment(kind: .file, name: "a", data: Data([1])) }
        let first = try await within { try await client.chatSend(sessionId: "s1", text: "a", attachments: [id]) }
        XCTAssertEqual(first, .submitted)
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "again", attachments: [id]) }
        XCTAssertEqual(chat.attachmentSends.count, 1)
    }

    func testUploadIsConsumedWhateverTheOutcome() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        chat.setSendOutcome(.failed, for: "s1")
        let client = try await connect(makeHost(chat: chat))
        let toGhost = try await within { try await client.uploadAttachment(kind: .file, name: "a", data: Data([1])) }
        let toFailing = try await within { try await client.uploadAttachment(kind: .file, name: "b", data: Data([2])) }
        let ghost = try await within { try await client.chatSend(sessionId: "ghost", text: "x", attachments: [toGhost]) }
        XCTAssertEqual(ghost, .notFound)
        let failed = try await within { try await client.chatSend(sessionId: "s1", text: "x", attachments: [toFailing]) }
        XCTAssertEqual(failed, .failed)
        for id in [toGhost, toFailing] {
            await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: [id]) }
        }
    }

    func testAChatSendThatFailsTheChecksUsesNoUpload() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let a = try await within { try await client.uploadAttachment(kind: .file, name: "a", data: Data([1])) }
        let b = try await within { try await client.uploadAttachment(kind: .file, name: "b", data: Data([2])) }
        let unfinished = try await within {
            try await client.call { .attachBegin(callId: $0, kind: .file, name: "c", size: 4) }
        }
        guard case let .attachReady(_, c) = unfinished else { return XCTFail("expected attach.ready") }

        // An id the host does not hold, an upload not yet ended, the same id twice, too many ids, a text that
        // is too long: each is refused whole, and none uses a or b.
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: [a, "nope"]) }
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: [a, c]) }
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: [a, b, a]) }
        let six = [a, b, "d", "e", "f", "g"]
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: "x", attachments: six) }
        let long = String(repeating: "x", count: 16_385)
        await expectRemote("bad_request") { try await client.chatSend(sessionId: "s1", text: long, attachments: [a]) }
        XCTAssertTrue(chat.attachmentSends.isEmpty)

        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "x", attachments: [a, b]) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["a", "b"])
    }

    func testFiveAttachmentsInOneMessage() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        var ids: [String] = []
        for number in 0..<ShellXLink.maxAttachmentsPerMessage {
            let bytes = Data([UInt8(number)])
            ids.append(try await within { try await client.uploadAttachment(kind: .file, name: "f\(number)", data: bytes) })
        }
        let all = ids
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: all) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["f0", "f1", "f2", "f3", "f4"])
    }

    // MARK: - Sessions

    func testUploadsDieWithTheSession() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let rig = makeHost(chat: chat)
        let first = try await connect(rig)
        let id = try await within { try await first.uploadAttachment(kind: .file, name: "a", data: Data([1])) }

        let second = try await connect(rig)
        await expectRemote("bad_request") { try await second.chatSend(sessionId: "s1", text: "x", attachments: [id]) }
        XCTAssertTrue(chat.attachmentSends.isEmpty)
        // The other session's attempt did not take the upload from its own session.
        let outcome = try await within { try await first.chatSend(sessionId: "s1", text: "x", attachments: [id]) }
        XCTAssertEqual(outcome, .submitted)

        // After a session ends, a new one of the same phone starts with nothing held.
        let third = try await within { try await first.uploadAttachment(kind: .file, name: "b", data: Data([2])) }
        await first.close()
        let reconnected = try await connect(rig)
        await expectRemote("bad_request") { try await reconnected.chatSend(sessionId: "s1", text: "x", attachments: [third]) }
    }

    // MARK: - One upload at a time

    /// The host drops an unfinished upload at every `attach.begin`, so a client must not run two uploads at once.
    func testConcurrentUploadsOnOneClientBothArrive() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let first = Data((0..<100_000).map { UInt8($0 % 251) })
        let second = Data((0..<120_000).map { UInt8(($0 * 7) % 253) })

        async let firstId = client.uploadAttachment(kind: .file, name: "first.bin", data: first)
        async let secondId = client.uploadAttachment(kind: .image, name: "second.jpg", data: second)
        // Every step is a call with a 10 s timeout, so a lost answer fails this instead of hanging it.
        let ids = try await [firstId, secondId]

        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "both", attachments: ids) }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(chat.attachmentSends.first?.attachments, [
            ChatAttachment(kind: .file, name: "first.bin", data: first),
            ChatAttachment(kind: .image, name: "second.jpg", data: second),
        ])
    }

    func testCancelledUploadReleasesTheTurn() async throws {
        let client = try await connectToAHostThatStallsTheFirstUpload()
        let progress = Collector<Int>()
        let first = Task {
            try await client.uploadAttachment(kind: .file, name: "a", data: Data(count: 100_000)) { progress.append($0) }
        }
        // The first upload has its turn and now waits for the answer to its second chunk, which never comes.
        let running = await eventually { progress.items == [45_000] }
        XCTAssertTrue(running, "the first upload did not start")
        let second = Task { try await client.uploadAttachment(kind: .file, name: "b", data: Data([1, 2, 3])) }
        let queued = await waitForQueue(of: client, toReach: 1)
        XCTAssertTrue(queued, "the second upload did not wait for its turn")

        first.cancel()
        do {
            let id = try await within { try await first.value }
            XCTFail("the cancelled upload returned \(id)")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let id = try await within { try await second.value }
        XCTAssertEqual(id, "U2")
    }

    func testCancelledWaiterLeavesTheQueue() async throws {
        let client = try await connectToAHostThatStallsTheFirstUpload()
        let progress = Collector<Int>()
        let first = Task {
            try await client.uploadAttachment(kind: .file, name: "a", data: Data(count: 100_000)) { progress.append($0) }
        }
        let running = await eventually { progress.items == [45_000] }
        XCTAssertTrue(running, "the first upload did not start")
        let middle = Task { try await client.uploadAttachment(kind: .file, name: "b", data: Data([1])) }
        let last = Task { try await client.uploadAttachment(kind: .file, name: "c", data: Data([2])) }
        let queued = await waitForQueue(of: client, toReach: 2)
        XCTAssertTrue(queued, "the two uploads did not wait for their turn")

        // A waiter that gives up is out of the queue at once, and the turn skips it.
        middle.cancel()
        do {
            let id = try await within { try await middle.value }
            XCTFail("the cancelled waiter returned \(id)")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let afterCancel = await waitForQueue(of: client, toReach: 1)
        XCTAssertTrue(afterCancel, "the cancelled waiter is still queued")

        first.cancel()
        _ = await first.result
        // The host saw one begin from the first upload and one from the last: the waiter that left sent nothing.
        let id = try await within { try await last.value }
        XCTAssertEqual(id, "U2")
    }

    func testAFailedUploadReleasesTheTurn() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        async let refused: String = client.uploadAttachment(
            kind: .file, name: "big", data: Data(count: ShellXLink.maxAttachmentBytes + 1))
        async let fine = client.uploadAttachment(kind: .file, name: "ok", data: Data([1, 2]))
        do {
            let id = try await refused
            XCTFail("the oversize upload returned \(id)")
        } catch let LinkClientError.remote(code, _) {
            XCTAssertEqual(code, "too_large")
        }
        let id = try await fine
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "", attachments: [id]) }
        XCTAssertEqual(outcome, .submitted)
    }

    // MARK: - One message at a time

    /// Ruling R14(a): a message keeps the upload turn from its first `attach.begin` until its `chat.send` is
    /// answered, so another message's uploads never come between them.
    func testAMessageHoldsTheUploadTurnUntilItsSendIsAnswered() async throws {
        let sendArrived = Flag()
        let client = try await connectToAHostThatStallsTheFirstUpload(stalls: false, sendArrived: sendArrived)
        let message = Task {
            try await client.chatSend(
                sessionId: "s1", text: "look", uploading: [ChatAttachment(kind: .file, name: "a", data: Data([1]))])
        }
        // Its upload is done, and its `chat.send`, which this host never answers, has reached the host.
        let sent = await eventually { sendArrived.isSet }
        XCTAssertTrue(sent, "the message's chat.send did not arrive")

        let other = Task { try await client.uploadAttachment(kind: .file, name: "b", data: Data([2])) }
        let queued = await waitForQueue(of: client, toReach: 1)
        XCTAssertTrue(queued, "another upload went ahead while the message waited for its answer")

        message.cancel()
        do {
            let outcome = try await within { try await message.value }
            XCTFail("the cancelled message returned \(outcome)")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let id = try await within { try await other.value }
        XCTAssertEqual(id, "U2")
    }

    /// Two messages of five attachments sent at once from one phone both arrive whole: with the turn held per
    /// message, neither's upload is dropped to make room for the other's.
    func testTwoMessagesOfFiveAttachmentsAtOnceBothArrive() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        func five(_ prefix: String) -> [ChatAttachment] {
            (0..<ShellXLink.maxAttachmentsPerMessage).map {
                ChatAttachment(kind: .file, name: "\(prefix)\($0)", data: Data(count: 50_000))
            }
        }

        async let first = client.chatSend(sessionId: "s1", text: "one", uploading: five("a"))
        async let second = client.chatSend(sessionId: "s1", text: "two", uploading: five("b"))
        let outcomes = try await [first, second]

        XCTAssertEqual(outcomes, [.submitted, .submitted])
        let byText = Dictionary(uniqueKeysWithValues: chat.attachmentSends.map { ($0.text, $0.attachments.map(\.name)) })
        XCTAssertEqual(byText["one"], ["a0", "a1", "a2", "a3", "a4"])
        XCTAssertEqual(byText["two"], ["b0", "b1", "b2", "b3", "b4"])
    }

    /// The bytes of every attachment, counted over the whole message; a refused upload stops the message before
    /// its `chat.send`, as a `MessageUploadError` that carries the host's refusal.
    func testAMessageReportsItsProgressAndStopsAtARefusedUpload() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        let progress = Collector<Int>()
        let outcome = try await within {
            try await client.chatSend(sessionId: "s1", text: "both", uploading: [
                ChatAttachment(kind: .file, name: "big", data: Data(count: 100_000)),
                ChatAttachment(kind: .image, name: "small.jpg", data: Data([1, 2, 3])),
            ]) { progress.append($0) }
        }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(progress.items, [45_000, 90_000, 100_000, 100_003])
        XCTAssertEqual(chat.attachmentSends.first?.attachments.map(\.name), ["big", "small.jpg"])

        do {
            let refused = try await within {
                try await client.chatSend(sessionId: "s1", text: "x", uploading: [
                    ChatAttachment(kind: .file, name: "fine", data: Data([1])),
                    ChatAttachment(kind: .file, name: "empty", data: Data()),
                ])
            }
            XCTFail("a message with an empty attachment returned \(refused)")
        } catch let error as MessageUploadError {
            guard case let LinkClientError.remote(code, _) = error.cause else {
                return XCTFail("expected a refusal, got \(error.cause)")
            }
            XCTAssertEqual(code, "bad_request")
        }
        XCTAssertEqual(chat.attachmentSends.count, 1, "the refused message was not sent")
    }

    // MARK: - Hosts without attachments

    func testHostWithoutAttachmentsAdvertisesNothing() async throws {
        let chat = FakeChatSource(["s1": []])
        let client = try await connect(makeHost(chat: chat))
        XCTAssertTrue(client.hostFeatures.isEmpty)
        await expectRemote("unsupported") { try await client.uploadAttachment(kind: .image, name: "a.jpg", data: Data([1])) }
        await expectRemote("unsupported") {
            try await client.call { .attachChunk(callId: $0, attachmentId: "a1", offset: 0, data: Data([1])) }
        }
        await expectRemote("unsupported") {
            try await client.call { .attachEnd(callId: $0, attachmentId: "a1", sha256: Data(count: 32)) }
        }
        // A message that carries attachments is refused, not typed without them.
        await expectRemote("unsupported") { try await client.chatSend(sessionId: "s1", text: "see", attachments: ["a1"]) }
        XCTAssertTrue(chat.sends.isEmpty && chat.attachmentSends.isEmpty, "nothing was typed")
        // Text alone still works.
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "hi") }
        XCTAssertEqual(outcome, .submitted)
    }

    func testHostWithoutChatAdvertisesNothing() async throws {
        let client = try await connect(makeHost(chat: nil))
        XCTAssertTrue(client.hostFeatures.isEmpty)
        await expectRemote("unsupported") { try await client.uploadAttachment(kind: .file, name: "a", data: Data([1])) }
    }

    // MARK: - AgentChatSource defaults

    private struct TextOnlyChat: AgentChatSource {
        let log = Collector<String>()

        func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? { nil }
        func send(sessionId: String, text: String) async -> ChatSendOutcome {
            log.append(text)
            return .submitted
        }
        func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome { .sent }
        func entries() -> AsyncStream<ChatPush> { AsyncStream { $0.finish() } }
    }

    func testTheDefaultSourceTakesNoAttachments() async {
        let source = TextOnlyChat()
        XCTAssertFalse(source.acceptsAttachments)
        let plain = await source.send(sessionId: "s1", text: "hi", attachments: [])
        XCTAssertEqual(plain, .submitted)
        XCTAssertEqual(source.log.items, ["hi"])
        let withFile = await source.send(
            sessionId: "s1", text: "hi", attachments: [ChatAttachment(kind: .file, name: "a", data: Data([1]))])
        XCTAssertEqual(withFile, .failed)
        XCTAssertEqual(source.log.items, ["hi"], "a source that takes no attachments types nothing for them")
    }

    // MARK: - Helpers

    private struct Rig {
        let host: LinkHost
        let hostKey: NoiseStaticKey
        let clientKey: NoiseStaticKey
    }

    private func makeHost(chat: (any AgentChatSource)?, clock: UploadTestClock? = nil) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let trusted: Set<Data> = [clientKey.publicKey]
        var timings = LinkTimings.standard
        if let clock { timings.now = { clock.now() } }
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: FakeFeedSource(), sessions: nil, chat: chat,
            hostVersion: "test-host", machineName: "Test Mac", timings: timings)
        return Rig(host: host, hostKey: hostKey, clientKey: clientKey)
    }

    private func startServe(_ host: LinkHost) -> (any RelayCircuit, Flag) {
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let done = Flag()
        serveTasks.append(Task {
            await host.serve(hostEnd)
            done.set()
        })
        return (clientEnd, done)
    }

    private func connect(_ rig: Rig) async throws -> LinkClient {
        let (end, _) = startServe(rig.host)
        let client = try await LinkClient.connect(
            end, key: rig.clientKey, hostKey: rig.hostKey.publicKey, clientVersion: "test-client",
            deviceName: "Test Phone", timings: .standard)
        clients.append(client)
        return client
    }

    /// A raw channel past `hello` / `welcome`, which must list exactly `features`.
    private func rawEstablished(_ end: any RelayCircuit, _ rig: Rig, features: [String]) async throws -> SecureChannel {
        let hostPublic = rig.hostKey.publicKey
        let raw = try await SecureChannel.open(end, role: .initiator, key: rig.clientKey, trusts: { $0 == hostPublic })
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        let welcome = try await raw.receive()
        XCTAssertEqual(
            welcome, .welcome(protocolVersion: 1, hostVersion: "test-host", machineName: "Test Mac", features: features))
        return raw
    }

    /// A client connected to a scripted host that takes uploads as `U1`, `U2`, ... and never answers a `chat.send`
    /// (it sets `sendArrived` when one comes). Unless `stalls` is false, it never answers the second chunk of `U1`
    /// either, so the first upload stays running until the test cancels it.
    private func connectToAHostThatStallsTheFirstUpload(
        stalls: Bool = true, sendArrived: Flag = Flag()
    ) async throws -> LinkClient {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        serveTasks.append(Task {
            do {
                let channel = try await SecureChannel.open(hostEnd, role: .responder, key: hostKey, trusts: { _ in true })
                _ = try await channel.receive()
                try await channel.send(.welcome(
                    protocolVersion: 1, hostVersion: "test", machineName: "mac", features: ["attachments"]))
                var held: [String: Int] = [:]
                var begun = 0
                while true {
                    switch try await channel.receive() {
                    case let .attachBegin(callId, _, _, _):
                        begun += 1
                        held["U\(begun)"] = 0
                        try await channel.send(.attachReady(callId: callId, attachmentId: "U\(begun)"))
                    case let .attachChunk(callId, id, offset, data):
                        if stalls, id == "U1", offset > 0 { continue }
                        held[id, default: 0] += data.count
                        try await channel.send(.attachChunkResult(callId: callId, attachmentId: id, received: held[id] ?? 0))
                    case let .attachEnd(callId, id, _):
                        try await channel.send(.attachEndResult(callId: callId, attachmentId: id))
                    case .chatSend:
                        sendArrived.set()
                    default:
                        continue
                    }
                }
            } catch {
                // The circuit closed: the test is over.
            }
        })
        let client = try await LinkClient.connect(
            clientEnd, key: clientKey, hostKey: hostKey.publicKey, clientVersion: "test-client",
            deviceName: "Test Phone", timings: .standard)
        clients.append(client)
        return client
    }

    private func waitForQueue(of client: LinkClient, toReach count: Int) async -> Bool {
        for _ in 0..<400 {
            if await client.uploadsWaiting == count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    /// `attach.begin` of an image of `size` bytes; returns the host's id.
    private func begin(_ raw: SecureChannel, size: Int) async throws -> String {
        try await raw.send(.attachBegin(callId: "begin", kind: .image, name: "a.jpg", size: size))
        let ready = try await within { try await raw.receive() }
        guard case let .attachReady("begin", id) = ready else {
            XCTFail("expected attach.ready, got \(ready)")
            throw TimedOut()
        }
        return id
    }

    private func expectError(
        _ raw: SecureChannel, _ code: String, callId: String, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let answer = try await within { try await raw.receive() }
        guard case let .error(got, _, id) = answer else {
            return XCTFail("expected error \(code), got \(answer)", file: file, line: line)
        }
        XCTAssertEqual(got, code, file: file, line: line)
        XCTAssertEqual(id, callId, file: file, line: line)
    }

    /// Fails unless `operation` throws the host's `error` with `code` (`LinkClientError.remote`).
    private func expectRemote<T: Sendable>(
        _ code: String, file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        do {
            let value = try await within { try await operation() }
            XCTFail("expected error \(code), got \(value)", file: file, line: line)
        } catch let LinkClientError.remote(got, _) {
            XCTAssertEqual(got, code, file: file, line: line)
        } catch {
            XCTFail("expected error \(code), got \(error)", file: file, line: line)
        }
    }

    private func digest(_ bytes: Data) -> Data {
        Data(SHA256.hash(data: bytes))
    }
}

/// A clock the test moves by hand, for the host's upload expiry.
final class UploadTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var elapsed = Duration.zero

    func advance(_ duration: Duration) {
        lock.withLock { elapsed += duration }
    }

    func now() -> ContinuousClock.Instant {
        lock.withLock { start + elapsed }
    }
}
