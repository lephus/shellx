import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

/// Terminal views and `terminal.create` over a Link session (PROTOCOL.md section 11).
final class TerminalSessionTests: TerminalSessionTestCase {
    func testTerminalCallsWithoutSources() async throws {
        let raw = try await rawSession(makeHost())
        try await raw.send(.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30))
        try await expectError(raw, "unsupported", callId: "c1")
        try await raw.send(.terminalCreate(callId: "c2", workspaceId: "ws-1"))
        try await expectError(raw, "unsupported", callId: "c2")

        try await raw.send(.terminalViewInput(terminalId: "t-1", units: [.text("a")]))
        try await raw.send(.terminalViewResize(terminalId: "t-1", cols: 80, rows: 24))
        try await raw.send(.terminalViewResync(terminalId: "t-1"))
        try await raw.send(.terminalViewClose(terminalId: "t-1"))
        try await raw.send(.ping(nonce: 7))
        await assertEqual(try await within { try await raw.receive() }, .pong(nonce: 7), "nothing answered the four")

        try await raw.send(.terminalViewOpenResult(callId: "c3", outcome: .ok))
        try await expectError(raw, "bad_request", callId: "c3")
        try await raw.send(.terminalCreateResult(callId: "c4", outcome: .ok, terminalId: nil))
        try await expectError(raw, "bad_request", callId: "c4")
        try await raw.send(.terminalViewEnded(terminalId: "t-1", reason: .gone))
        try await expectError(raw, "bad_request", callId: nil)
    }

    func testFramesFromAClientAreBadRequest() async throws {
        let raw = try await rawSession(makeHost())
        try await raw.send(.terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, part: 1, parts: 2)))
        try await expectError(raw, "bad_request", callId: nil)
    }

    // MARK: - terminal.create

    func testWelcomeListsTerminalCreateOnlyWithACreator() async throws {
        let withCreator = try await welcomeFeatures(makeHost(terminalCreator: FakeTerminalCreator()))
        XCTAssertEqual(withCreator, ["terminal_create"])
        let without = try await welcomeFeatures(makeHost())
        XCTAssertEqual(without, [])
    }

    func testCreateReachesTheCreator() async throws {
        let creator = FakeTerminalCreator()
        creator.setCreate(.ok, terminalId: "t-9")
        let client = try await connect(makeHost(terminalCreator: creator))
        let created = try await within { try await client.createTerminal(workspaceId: "ws-1") }
        XCTAssertEqual(created.outcome, .ok)
        XCTAssertEqual(created.terminalId, "t-9")
        for outcome in [WorkspaceControlOutcome.notFound, .refused, .failed, .other("busy")] {
            creator.setCreate(outcome, terminalId: "t-ignored")
            let answer = try await within { try await client.createTerminal(workspaceId: "ws-1") }
            XCTAssertEqual(answer.outcome, outcome)
            XCTAssertNil(answer.terminalId, "terminal_id only with ok")
        }
        XCTAssertEqual(creator.calls, Array(repeating: "ws-1", count: 5))
    }

    func testSlowCreateDoesNotBlockTheSession() async throws {
        let creator = FakeTerminalCreator()
        let gate = Gate()
        creator.hold(until: gate)
        let client = try await connect(makeHost(terminalCreator: creator))
        let pending = Task { try await client.createTerminal(workspaceId: "ws-1") }
        _ = try await within { try await client.snapshot() }     // answered while the create waits
        gate.open()
        let created = try await pending.value
        XCTAssertEqual(created.outcome, .ok)
    }

    func expectError(_ raw: SecureChannel, _ code: String, callId: String?,
                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let message = try await within { try await raw.receive() }
        guard case let .error(got, _, gotCallId) = message else {
            return XCTFail("expected error \(code), got \(message)", file: file, line: line)
        }
        XCTAssertEqual(got, code, file: file, line: line)
        XCTAssertEqual(gotCallId, callId, file: file, line: line)
    }
}
