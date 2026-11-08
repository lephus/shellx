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

    // MARK: - terminal views

    func testWelcomeListsTerminalViewOnlyWithASource() async throws {
        await assertEqual(try await welcomeFeatures(makeHost(terminalViews: FakeTerminalViewSource())), ["terminal_view"])
        await assertEqual(try await welcomeFeatures(makeHost(terminalViews: FakeTerminalViewSource(),
                                                             terminalCreator: FakeTerminalCreator())),
                          ["terminal_view", "terminal_create"])
    }

    func testOpenAnswersBeforeTheFirstFrame() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 46, rows: 2, text: ["$"]))) }
        let raw = try await rawSession(makeHost(terminalViews: views))
        try await raw.send(.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30))
        await assertEqual(try await within { try await raw.receive() }, .terminalViewOpenResult(callId: "c1", outcome: .ok))
        let next = try await within { try await raw.receive() }
        guard case let .terminalViewFrame("t-1", part) = next else { return XCTFail("no frame") }
        XCTAssertEqual(part.revision, 1)
        XCTAssertEqual(part.head?.kind, .snapshot)
    }

    func testOpenClampsTheSizeAndRefusesNonPositiveOnes() async throws {
        let views = FakeTerminalViewSource()
        let client = try await connect(makeHost(terminalViews: views))
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 10, rows: 2) }
        try await client.closeTerminalView(terminalId: "t-1")
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 999, rows: 999) }
        await expectRemote("bad_request") { try await client.openTerminalView(terminalId: "t-1", cols: 0, rows: 24) }
        XCTAssertEqual(views.opens, [.init(terminalId: "t-1", cols: 20, rows: 5), .init(terminalId: "t-1", cols: 300, rows: 120)])
    }

    func testOpenOutcomesFromTheSource() async throws {
        let views = FakeTerminalViewSource()
        views.refuse("gone", with: .notFound)
        views.refuse("mdm", with: .refused)
        views.refuse("bad", with: .failed)
        let client = try await connect(makeHost(terminalViews: views))
        for (id, outcome) in [("gone", TerminalViewOpenOutcome.notFound), ("mdm", .refused), ("bad", .failed)] {
            await assertEqual(try await within { try await client.openTerminalView(terminalId: id, cols: 46, rows: 30) }, outcome)
        }
    }

    func testAnotherTerminalIsBusy() async throws {
        let views = FakeTerminalViewSource()
        let client = try await connect(makeHost(terminalViews: views))
        await assertEqual(try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }, .ok)
        await assertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 46, rows: 30) }, .busy)
        XCTAssertEqual(views.opens.map(\.terminalId), ["t-1"])
        XCTAssertEqual(views.views[0].calls, [], "the first view stays open")
    }

    func testReopenRestartsTheView() async throws {   // Review Focus 3
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, n in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["view \(n)"])))
            if n == 1 { view.produceOnDemand { i in i <= 50 ? .frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "tick \(i)"])) : nil } }
        }
        let slow = PausableBox()
        let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
        let pushes = collect(client.terminalPushes)
        slow.circuit.pause(afterSends: 2)                   // the answer and the first snapshot, then the network stalls
        await assertEqual(try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }, .ok)
        let second = Task { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        try await Task.sleep(for: .milliseconds(100))
        slow.circuit.resume()
        let secondOutcome = try await second.value
        XCTAssertEqual(secondOutcome, .ok)
        let settled = await waitFor(pushes) { assembledText($0) == ["view 2"] }
        XCTAssertTrue(settled)
        let state = assembled(pushes.items)
        XCTAssertEqual(state.revisions.first, 1)
        XCTAssertEqual(state.kinds.first, .snapshot)
        XCTAssertEqual(state.screen.screenText(), ["view 2"], "no frame of the first view after the second ok")
        XCTAssertEqual(views.views[0].calls.filter { $0 == .close }.count, 1)
    }

    func testCloseEndsTheViewAndFreesTheSession() async throws {
        let views = FakeTerminalViewSource()
        let client = try await connect(makeHost(terminalViews: views))
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }
        try await client.closeTerminalView(terminalId: "t-1")
        await assertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 46, rows: 30) }, .ok)
        XCTAssertEqual(views.views[0].calls, [.close])
    }

    func testSourceEndingSendsEnded() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["$"])), .ended(.gone)) }
        let client = try await connect(makeHost(terminalViews: views))
        let pushes = collect(client.terminalPushes)
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .gone)) }
        XCTAssertTrue(ended)
        await assertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 20, rows: 5) }, .ok)
        XCTAssertEqual(views.views[0].calls, [.close])
    }

    func testSessionEndClosesTheView() async throws {
        let views = FakeTerminalViewSource()
        let client = try await connect(makeHost(terminalViews: views))
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }
        await client.close()
        let closed = await eventually { views.views.first?.calls == [.close] }
        XCTAssertTrue(closed, "the terminal must go back to the Mac's size")
    }

    func testFramesArriveInOrderAfterOpened() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 2, text: ["a", "b"])),
                      .frame(deltaFrame(cols: 20, rows: 2, replacing: [0: "c"])),
                      .frame(deltaFrame(cols: 20, rows: 2, replacing: [1: "d"])))
        }
        let client = try await connect(makeHost(terminalViews: views))
        let pushes = collect(client.terminalPushes)
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        let done = await waitFor(pushes) { assembled($0).revisions.last == 3 }
        XCTAssertTrue(done)
        XCTAssertEqual(pushes.items.first, .opened(terminalId: "t-1"))
        XCTAssertEqual(assembled(pushes.items).revisions, [1, 2, 3])
        XCTAssertEqual(assembled(pushes.items).screen.screenText(), ["c", "d"])
    }

    // MARK: - input, resize, resync

    func testInputReachesTheViewInOrder() async throws {
        let (client, view) = try await openedView()
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls")])
        try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.enter, mods: [])])
        try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.letter("c"), mods: [.ctrl])])
        let all = await eventually { view.calls.count == 3 }
        XCTAssertTrue(all)
        XCTAssertEqual(view.calls, [.input([.text("ls")]), .input([.key(.enter, mods: [])]), .input([.key(.letter("c"), mods: [.ctrl])])])
    }

    func testInvalidInputIsBadRequestAndNotApplied() async throws {
        let views = FakeTerminalViewSource()
        let raw = try await rawSession(makeHost(terminalViews: views))
        try await raw.send(.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30))
        _ = try await within { try await raw.receive() }
        try await raw.send(.terminalViewInput(terminalId: "t-1", units: [.text("ls\n")]))
        try await expectError(raw, "bad_request", callId: nil)
        XCTAssertEqual(views.views[0].calls, [])
    }

    func testClientRefusesTypedNewlineBeforeSending() async throws {   // Review Focus 2
        let (client, view) = try await openedView()
        do {
            try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls\n")])
            XCTFail("a newline must be key enter")
        } catch let error as TerminalInputError {
            XCTAssertFalse(error.reason.contains("ls"))
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(view.calls, [])
    }

    func testInputResizeAndResyncForAnotherTerminalAreNotOpen() async throws {
        let (client, view, pushes) = try await openedViewWithPushes()
        try await client.sendTerminalInput(terminalId: "t-2", units: [.text("x")])
        try await client.resizeTerminalView(terminalId: "t-2", cols: 80, rows: 24)
        try await client.resyncTerminalView(terminalId: "t-2")
        let three = await waitFor(pushes) { $0.filter { $0 == .ended(terminalId: "t-2", reason: .notOpen) }.count == 3 }
        XCTAssertTrue(three)
        XCTAssertEqual(view.calls, [])
    }

    func testInputAfterCloseIsNotOpen() async throws {
        let (client, _, pushes) = try await openedViewWithPushes()
        try await client.closeTerminalView(terminalId: "t-1")
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("x")])
        let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .notOpen)) }
        XCTAssertTrue(ended)
    }

    func testResizeIsClampedAndKeepsOrderWithInput() async throws {
        let (client, view) = try await openedView()
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("a")])
        try await client.resizeTerminalView(terminalId: "t-1", cols: 10, rows: 2)
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("b")])
        try await client.resizeTerminalView(terminalId: "t-1", cols: 999, rows: 999)
        let all = await eventually { view.calls.count == 4 }
        XCTAssertTrue(all)
        XCTAssertEqual(view.calls, [.input([.text("a")]), .resize(cols: 20, rows: 5), .input([.text("b")]), .resize(cols: 300, rows: 120)])
    }

    func testInputBeforeCloseIsStillApplied() async throws {   // Review Focus 3
        let (client, view) = try await openedView()
        let gate = Gate()
        view.holdInput(until: gate)
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls")])
        try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.enter, mods: [])])
        try await client.closeTerminalView(terminalId: "t-1")
        try await Task.sleep(for: .milliseconds(100))
        gate.open()
        let closed = await eventually { view.calls.last == .close }
        XCTAssertTrue(closed)
        XCTAssertEqual(view.calls, [.input([.text("ls")]), .input([.key(.enter, mods: [])]), .close])
    }

    func testQueuedInputIsBounded() async throws {
        let (client, view) = try await openedView()
        let gate = Gate()
        view.holdInput(until: gate)
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("0")])
        let started = await eventually { view.inputsStarted == 1 }
        XCTAssertTrue(started)
        for i in 1...70 { try await client.sendTerminalInput(terminalId: "t-1", units: [.text("\(i)")]) }
        _ = try await within { try await client.snapshot() }       // the host has read all 71
        gate.open()
        let applied = await eventually { view.calls.count == 65 }
        XCTAssertTrue(applied)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(view.calls, (0...64).map { .input([.text("\($0)")]) })
    }

    func testResyncSendsOneSnapshotAndDropsStaleDeltas() async throws {
        let views = FakeTerminalViewSource()
        let answer = Gate()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["one"])))
            view.answerSnapshotRequests(after: answer) {
                [.frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "stale"])), .frame(snapshotFrame(cols: 20, rows: 1, text: ["again"]))]
            }
        }
        let client = try await connect(makeHost(terminalViews: views))
        let pushes = collect(client.terminalPushes)
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        let first = await waitFor(pushes) { assembled($0).revisions == [1] }
        XCTAssertTrue(first)
        for _ in 0..<3 { try await client.resyncTerminalView(terminalId: "t-1") }
        _ = try await within { try await client.snapshot() }       // the host has read all three resyncs
        answer.open()
        let again = await waitFor(pushes) { assembledText($0) == ["again"] }
        XCTAssertTrue(again)
        XCTAssertEqual(views.views[0].snapshotRequests, 1, "resyncs before the snapshot share it")
        XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
        XCTAssertEqual(assembled(pushes.items).revisions, [1, 2])
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
