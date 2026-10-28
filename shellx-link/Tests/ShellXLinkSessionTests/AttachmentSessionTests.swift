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

    func testSixthPendingUploadIsRefused() async throws {
        let chat = FakeChatSource(["s1": []], acceptsAttachments: true)
        let client = try await connect(makeHost(chat: chat))
        var ids: [String] = []
        for number in 0..<4 {
            let bytes = Data([UInt8(number)])
            ids.append(try await within { try await client.uploadAttachment(kind: .file, name: "f\(number)", data: bytes) })
        }
        // The fifth is only begun: an unfinished upload holds its place too.
        let fifth = try await within {
            try await client.call { .attachBegin(callId: $0, kind: .file, name: "f4", size: 1) }
        }
        guard case .attachReady = fifth else { return XCTFail("expected attach.ready, got \(fifth)") }
        await expectRemote("bad_request") { try await client.uploadAttachment(kind: .file, name: "f5", data: Data([5])) }

        // A chat.send that uses one frees its place.
        let firstId = ids[0]
        let outcome = try await within { try await client.chatSend(sessionId: "s1", text: "go", attachments: [firstId]) }
        XCTAssertEqual(outcome, .submitted)
        _ = try await within { try await client.uploadAttachment(kind: .file, name: "f5", data: Data([5])) }
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

    private func makeHost(chat: (any AgentChatSource)?) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let trusted: Set<Data> = [clientKey.publicKey]
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: FakeFeedSource(), sessions: nil, chat: chat,
            hostVersion: "test-host", machineName: "Test Mac", timings: .standard)
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
