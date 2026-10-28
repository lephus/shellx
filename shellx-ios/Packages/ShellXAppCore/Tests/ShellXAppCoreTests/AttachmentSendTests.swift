import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// Photos and files sent with a message from an agent's screen, through a real Link session to a
/// `FakeMac`: what reaches the Mac, what the phone refuses before any call, and
/// what the composer gets back when the Mac surely did not take the message.
@MainActor
final class AttachmentSendTests: XCTestCase {
    private func ref(_ mac: FakeMac, _ sessionId: String = "s1") -> SessionRef {
        SessionRef(machineID: mac.machine.machineID, sessionId: sessionId, agent: "claude", workspaceTitle: "shellx")
    }

    /// A Mac with one running session `s1` whose chat accepts messages.
    private func macWithSession(name: String = "MacBook Pro", acceptsAttachments: Bool = true) async -> FakeMac {
        let mac = FakeMac(name: name, acceptsAttachments: acceptsAttachments)
        await mac.upsertSession(agentSession("s1"))
        await mac.setHistory(sessionId: "s1", entries: [])
        return mac
    }

    /// A screenshot bigger than one upload chunk, so it goes up in several.
    private let shot = OutgoingAttachment(
        kind: .image, name: "shot.jpg", data: Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }))
    private let log = OutgoingAttachment(kind: .file, name: "build.log", data: Data("error: missing import\n".utf8))

    private func model(_ ref: SessionRef, _ rig: HubRig) -> AgentThreadModel {
        let model = AgentThreadModel(ref: ref, hub: rig.hub, store: rig.store, sleep: ManualSleeper().sleep)
        addTeardownBlock { @MainActor in await model.close() }
        return model
    }

    // MARK: - Sent

    func testPhotoAndTextReachTheMac() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        let model = model(ref(mac), rig)
        let result = await model.send("  sửa lỗi này \n", attachments: [shot], viaVoice: false)

        XCTAssertEqual(result, .sent(.submitted))
        XCTAssertFalse(result.keepsDraft)
        let received = await mac.receivedAttachments
        XCTAssertEqual(received, [ChatAttachment(kind: .image, name: "shot.jpg", data: shot.data)])
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "sửa lỗi này")])
        XCTAssertNil(model.uploadProgress, "no progress once the message is sent")

        // A second message, with two attachments.
        let agentResult = await model.send("còn file này", attachments: [log, shot], viaVoice: false)
        XCTAssertEqual(agentResult, .sent(.submitted))
        XCTAssertNil(model.uploadProgress)
        let all = await mac.receivedAttachments
        XCTAssertEqual(all.suffix(2), [
            ChatAttachment(kind: .file, name: "build.log", data: log.data),
            ChatAttachment(kind: .image, name: "shot.jpg", data: shot.data),
        ])
    }

    func testAttachmentOnlyMessageIsSent() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        let model = model(ref(mac), rig)
        let result = await model.send(" \n ", attachments: [log], viaVoice: false)

        XCTAssertEqual(result, .sent(.submitted))
        var sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "")])
        let received = await mac.receivedAttachments
        XCTAssertEqual(received, [ChatAttachment(kind: .file, name: "build.log", data: log.data)])

        let agentResult = await model.send("", attachments: [shot], viaVoice: false)
        XCTAssertEqual(agentResult, .sent(.submitted))
        sent = await mac.sentTexts
        XCTAssertEqual(sent.count, 2)
        // Still nothing to send without text or attachments.
        let empty = await model.send("  ", attachments: [], viaVoice: false)
        XCTAssertEqual(empty, .refused(.empty))
    }

    func testProgressCountsTheBytesOfEveryAttachment() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let seen = FractionLog()

        let outcome = try await rig.hub.chatSend(ref(mac), text: "xem giúp", attachments: [shot, log]) {
            seen.add($0)
        }

        XCTAssertEqual(outcome, .submitted)
        let fractions = seen.values
        XCTAssertEqual(fractions, fractions.sorted(), "progress only goes up")
        XCTAssertGreaterThan(fractions.count, 2, "one value per chunk: the photo takes three")
        XCTAssertEqual(fractions.last ?? 0, 1, accuracy: 1e-9)
        let total = Double(shot.data.count + log.data.count)
        XCTAssertEqual(fractions.first ?? 0, Double(ShellXLink.maxAttachmentChunkBytes) / total, accuracy: 1e-9)
    }

    func testUploadProgressShowsUntilTheMacAnswers() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let model = model(ref(mac), rig)
        XCTAssertNil(model.uploadProgress)
        // The uploads finish; the Mac holds the message itself.
        await mac.holdChat()

        let sending = Task { await model.send("xem ảnh", attachments: [shot], viaVoice: false) }
        let uploaded = await eventually { model.uploadProgress == 1 }
        XCTAssertTrue(uploaded, "every byte is up while the Mac has not answered")
        await mac.releaseChat()
        let result = await sending.value

        XCTAssertEqual(result, .sent(.submitted))
        XCTAssertNil(model.uploadProgress)
        // A late progress value of the finished send changes nothing.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(model.uploadProgress)
    }

    /// Ruling R14(a): two messages of five attachments sent at once to one Mac (two agent screens,
    /// say) both arrive whole. Each holds the upload turn until its `chat.send` is answered, so the Mac never
    /// drops one of a message's uploads to make room for the other's.
    func testTwoMessagesOfFiveAttachmentsAtOnceBothArrive() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        func five(_ prefix: String) -> [OutgoingAttachment] {
            (0..<ShellXLink.maxAttachmentsPerMessage).map {
                OutgoingAttachment(kind: .file, name: "\(prefix)\($0).log", data: Data(count: 50_000))
            }
        }
        let hub = rig.hub
        let target = ref(mac)

        async let first = hub.chatSend(target, text: "một", attachments: five("a")) { _ in }
        async let second = hub.chatSend(target, text: "hai", attachments: five("b")) { _ in }
        let outcomes = try await [first, second]

        XCTAssertEqual(outcomes, [.submitted, .submitted])
        let received = await mac.receivedAttachments.map(\.name)
        XCTAssertEqual(Set(received), Set(five("a").map(\.name) + five("b").map(\.name)))
        XCTAssertEqual(received.count, 10)
    }

    // MARK: - Refused on the phone

    func testSixAttachmentsAreRefusedOnThePhone() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let six = (1...6).map { OutgoingAttachment(kind: .file, name: "f\($0).txt", data: Data("\($0)".utf8)) }

        XCTAssertEqual(ComposerValidation("xem", attachmentCount: 6), .tooManyAttachments)
        XCTAssertEqual(ComposerValidation("xem", attachmentCount: 5), .ok("xem"))
        XCTAssertEqual(ComposerValidation.check(six), .tooManyAttachments)
        XCTAssertNil(ComposerValidation.check(Array(six.prefix(5))))

        let agentResult = await model(ref(mac), rig).send("xem 6 file", attachments: six, viaVoice: false)
        XCTAssertEqual(agentResult, .refused(.tooManyAttachments))
        XCTAssertTrue(agentResult.keepsDraft)

        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
        let received = await mac.receivedAttachments
        XCTAssertEqual(received, [])
    }

    func testOversizeAttachmentIsRefusedOnThePhone() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let big = OutgoingAttachment(kind: .file, name: "video.mov", data: Data(count: ShellXLink.maxAttachmentBytes + 1))
        let atLimit = OutgoingAttachment(kind: .file, name: "ok.bin", data: Data(count: ShellXLink.maxAttachmentBytes))

        XCTAssertEqual(ComposerValidation.check([log, big]), .attachmentTooLarge(name: "video.mov"))
        XCTAssertNil(ComposerValidation.check([atLimit]), "10 MiB exactly is allowed")

        let agentResult = await model(ref(mac), rig).send("xem video", attachments: [log, big], viaVoice: false)
        XCTAssertEqual(agentResult, .refused(.attachmentTooLarge(name: "video.mov")))
        XCTAssertTrue(agentResult.keepsDraft)

        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
        let received = await mac.receivedAttachments
        XCTAssertEqual(received, [])
    }

    // MARK: - Not taken: the composer keeps the draft

    func testFailedSendGivesTheAttachmentsBack() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let model = model(ref(mac), rig)

        // The link drops; the reconnect waits (its backoff is never released here).
        await mac.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first?.state == .reconnecting && model.offline }
        XCTAssertTrue(down)

        let agentResult = await model.send("sửa lỗi này", attachments: [shot], viaVoice: false)
        XCTAssertEqual(agentResult, .offline)
        XCTAssertTrue(agentResult.keepsDraft)
        XCTAssertNil(model.uploadProgress)

        let received = await mac.receivedAttachments
        XCTAssertEqual(received, [])
    }

    func testMessageTheMacDidNotTypeKeepsTheDraft() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        await mac.setSendOutcome(.busy)

        let agentResult = await model(ref(mac), rig).send("sửa lỗi này", attachments: [shot], viaVoice: false)
        XCTAssertEqual(agentResult, .sent(.busy))
        XCTAssertTrue(agentResult.keepsDraft)
    }

    func testMacWithoutTheFeatureGetsNothing() async throws {
        let mac = await macWithSession(acceptsAttachments: false)
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        // Finding M4: said apart from a send that failed and can be tried again.
        let agentResult = await model(ref(mac), rig).send("sửa lỗi này", attachments: [shot], viaVoice: false)
        XCTAssertEqual(agentResult, .attachmentsUnsupported)
        XCTAssertTrue(agentResult.keepsDraft)
        do {
            _ = try await rig.hub.chatSend(ref(mac), text: "x", attachments: [shot]) { _ in }
            XCTFail("a Mac without the feature is never sent attachments")
        } catch {
            XCTAssertEqual(error as? AttachmentSendError, .refused(code: "unsupported"))
        }
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
    }

    func testRefusedUploadKeepsTheDraft() async throws {
        let mac = await macWithSession()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        // An empty file: the Mac takes 1 byte to 10 MiB, so it refuses the upload.
        let empty = OutgoingAttachment(kind: .file, name: "empty.txt", data: Data())

        let agentResult = await model(ref(mac), rig).send("xem", attachments: [empty], viaVoice: false)

        // A refusal other than `unsupported` is a plain failure, to try again.
        XCTAssertEqual(agentResult, .notSent)
        XCTAssertTrue(agentResult.keepsDraft)
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
    }

    // MARK: - Gating

    func testAttachButtonOnlyForMacsThatAcceptThem() async throws {
        let takes = await macWithSession(name: "MacBook Pro")
        let refuses = FakeMac(name: "Mac mini", acceptsAttachments: false)
        let old = FakeMac(name: "iMac", servesSessionsAndChat: false)
        let rig = try await HubRig.make([takes, refuses, old], in: self)
        let synced = await eventually { rig.hub.machines.allSatisfy { $0.state == .online } }
        XCTAssertTrue(synced)

        XCTAssertTrue(rig.hub.acceptsAttachments(takes.machine.machineID))
        XCTAssertFalse(rig.hub.acceptsAttachments(refuses.machine.machineID))
        XCTAssertFalse(rig.hub.acceptsAttachments(old.machine.machineID), "no chat, no attachments")
        XCTAssertFalse(rig.hub.acceptsAttachments("mac-unknown"))

        // What the Mac said last stays known while it reconnects, so the button does not flicker.
        await takes.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first { $0.id == takes.machine.machineID }?.state == .reconnecting }
        XCTAssertTrue(down)
        XCTAssertTrue(rig.hub.acceptsAttachments(takes.machine.machineID))
    }
}

/// Progress values handed over from the Link client's actor.
private final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Double] = []

    var values: [Double] { lock.withLock { list } }

    func add(_ value: Double) {
        lock.withLock { list.append(value) }
    }
}
