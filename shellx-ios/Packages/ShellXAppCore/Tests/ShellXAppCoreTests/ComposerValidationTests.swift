import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// What the composer may send: trimmed, not empty, at most 16 384 UTF-8 bytes (the `chat.send`
/// limit), checked on the phone so the Mac never has to refuse it (Review Focus 4).
@MainActor
final class ComposerValidationTests: XCTestCase {
    func testWhitespaceIsEmpty() {
        XCTAssertEqual(ComposerValidation(""), .empty)
        XCTAssertEqual(ComposerValidation("  \n\t \u{3000}"), .empty)
        XCTAssertEqual(ComposerValidation("  chạy test đi \n"), .ok("chạy test đi"))
    }

    func testExactly16384BytesOk() {
        XCTAssertEqual(ComposerValidation.maxBytes, 16_384)
        let ascii = String(repeating: "a", count: 16_384)
        XCTAssertEqual(ComposerValidation("\n " + ascii + "  "), .ok(ascii), "counted after trimming")
        // "ệ" is 3 bytes: 5461 of them and one "a" make exactly 16 384.
        let vietnamese = String(repeating: "ệ", count: 5_461) + "a"
        XCTAssertEqual(vietnamese.utf8.count, 16_384)
        XCTAssertEqual(ComposerValidation(vietnamese), .ok(vietnamese))
    }

    func testOverlongTextRefusedBeforeSend() async throws {
        let text = String(repeating: "ệ", count: 5_461) + "ab"
        XCTAssertEqual(text.utf8.count, 16_385)
        XCTAssertEqual(ComposerValidation(text), .tooLong(bytes: 16_385))

        // With a live session to send to, an agent's screen still sends nothing.
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(agentSession("s1"))
        await mac.setHistory(sessionId: "s1", entries: [])
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let ref = SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        let model = AgentThreadModel(ref: ref, hub: rig.hub, store: rig.store, sleep: ManualSleeper().sleep)
        addTeardownBlock { @MainActor in await model.close() }

        let result = await model.send(text, viaVoice: true)

        XCTAssertEqual(result, .refused(.tooLong(bytes: 16_385)))
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
    }
}
