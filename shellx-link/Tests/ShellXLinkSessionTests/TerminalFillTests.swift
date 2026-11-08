import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

/// The history fill, the guards on what a source yields, and the backpressure of a view (PROTOCOL.md 11.8).
final class TerminalFillTests: TerminalSessionTestCase {
    func testSnapshotCarriesTheNewest240HistoryRows() async throws {
        let (client, pushes) = try await openWithSnapshot(history: (1...1000).map { "h\($0)" })
        let first = await firstFrameHead(pushes)
        XCTAssertEqual(first?.kind, .snapshot)
        XCTAssertEqual(first?.history, 240)
        _ = client
    }

    func testHistoryFramesFillUpToTheRowBudget() async throws {
        let source = (1...5000).map { "h\($0)" }
        let (_, pushes) = try await openWithSnapshot(history: source)
        let done = await waitFor(pushes) { assembled($0).revisions.last == 17 }
        XCTAssertTrue(done)
        await waitUntilQuiet(pushes)
        let state = assembled(pushes.items)
        XCTAssertEqual(state.kinds, [.snapshot] + Array(repeating: .history, count: 16))   // 240 + 15 x 240 + 160 = 4000
        XCTAssertEqual(state.screen.historyText(), Array(source.suffix(4000)))
    }

    func testHistoryFillStopsAtTheByteCap() async throws {
        let source = (1...3000).map { String(repeating: "x", count: 995) + String(format: "%05d", $0) }   // 1 000-byte rows
        let (_, pushes) = try await openWithSnapshot(history: source)
        await waitUntilQuiet(pushes)
        let bytes = try historyFrameBytes(pushes.items)            // encoded size of every part of every history frame
        XCTAssertLessThanOrEqual(bytes, ShellXLink.terminalHistoryFillMaxBytes)
        let history = assembled(pushes.items).screen.historyText()
        XCTAssertEqual(history.count, 480)                          // 240 + one 240-row frame (~247 KB); a second would pass the cap
        XCTAssertEqual(history, Array(source.suffix(480)))
    }

    func testDeltaDuringTheFillKeepsTheHistoryInOrder() async throws {   // Review Focus 5
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 2, text: ["s0", "s1"], history: (1...1000).map { "h\($0)" })))
        }
        let slow = PausableBox()
        let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
        let pushes = collect(client.terminalPushes)
        slow.circuit.pause(afterSends: 3)                  // answer, snapshot, first history frame; the second waits
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 2) }
        let stalled = await eventually { slow.circuit.sendsWaiting == 1 }
        XCTAssertTrue(stalled)
        views.views[0].emit(.frame(deltaFrame(cols: 20, rows: 2, replacing: [0: "n0", 1: "n1"], scroll: 2)))
        try await Task.sleep(for: .milliseconds(100))
        slow.circuit.resume()
        await waitUntilQuiet(pushes)
        let state = assembled(pushes.items)
        XCTAssertEqual(state.kinds, [.snapshot, .history, .history, .delta, .history, .history])
        XCTAssertEqual(state.screen.historyText(), (1...1000).map { "h\($0)" } + ["s0", "s1"])
        XCTAssertEqual(state.screen.screenText(), ["n0", "n1"])
    }

    func testNewSnapshotDropsTheOldFill() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["a"], history: (1...1000).map { "h\($0)" })),
                      .frame(snapshotFrame(cols: 30, rows: 1, text: ["b"])))
        }
        let slow = PausableBox()
        let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
        let pushes = collect(client.terminalPushes)
        slow.circuit.pause(afterSends: 1)                  // the answer; snapshot "a" waits on the network
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        let pulled = await eventually { views.views.first?.nextFrameCalls == 2 && slow.circuit.sendsWaiting == 1 }
        XCTAssertTrue(pulled, "snapshot b waits in the host while snapshot a is being sent")
        slow.circuit.resume()
        await waitUntilQuiet(pushes)
        XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
        XCTAssertEqual(assembled(pushes.items).screen.historyText(), [])
    }

    func testSlowPhoneGetsTheLastScreenWithBoundedFrames() async throws {   // Review Focus 4
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["tick 0"])))
            view.produceOnDemand { n in n <= 200 ? .frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "tick \(n)"])) : nil }
        }
        let slow = PausableBox()
        let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
        let pushes = collect(client.terminalPushes)
        slow.circuit.pause(afterSends: 2)                  // answer and snapshot
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 1) }
        try await Task.sleep(for: .milliseconds(300))
        let view = views.views[0]
        XCTAssertLessThanOrEqual(view.nextFrameCalls, 3, "the snapshot, the delta being sent, one waiting")
        slow.circuit.resume()
        let last = await waitFor(pushes) { assembledText($0) == ["tick 200"] }
        XCTAssertTrue(last)
        XCTAssertEqual(view.maxConcurrentNextFrameCalls, 1)
    }

    func testDeltaOfAnotherShapeAsksForASnapshot() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 10, rows: 2, text: ["a"])), .frame(deltaFrame(cols: 12, rows: 2, replacing: [0: "b"])))
            view.answerSnapshotRequests { [.frame(snapshotFrame(cols: 12, rows: 2, text: ["c"]))] }
        }
        let (_, pushes) = try await open(views)
        await waitUntilQuiet(pushes)
        XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
        XCTAssertEqual(views.views[0].snapshotRequests, 1)
    }

    func testFirstFrameThatIsNotASnapshotIsDropped() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(deltaFrame(cols: 10, rows: 1, replacing: [0: "x"])))
            view.answerSnapshotRequests { [.frame(snapshotFrame(cols: 10, rows: 1, text: ["s"]))] }
        }
        let (_, pushes) = try await open(views)
        await waitUntilQuiet(pushes)
        XCTAssertEqual(assembled(pushes.items).revisions, [1])
        XCTAssertEqual(assembledText(pushes.items), ["s"])
    }

    func testDeltaHistoryIsClamped() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: 10, rows: 2, text: ["a"])),
                      .frame(deltaFrame(cols: 10, rows: 2, replacing: [:], scroll: 3000, history: (1...2500).map { "b\($0)" })))
        }
        let (_, pushes) = try await open(views)
        await waitUntilQuiet(pushes)
        let history = assembled(pushes.items).screen.historyText()
        XCTAssertEqual(Array(history.suffix(2000)), (501...2500).map { "b\($0)" })
        XCTAssertEqual(history.count, 2002)                          // the two old screen rows, then 2 000 carried rows
    }

    func testGridBeyondTheLimitEndsTheView() async throws {
        let views = FakeTerminalViewSource()
        views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 1001, rows: 1, text: ["x"]))) }
        let (_, pushes) = try await open(views)
        let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .failed)) }
        XCTAssertTrue(ended)
    }

    // MARK: - Helpers

    /// Connects, opens `t-1` at 20 x 5 and returns the client and the started push collector.
    private func open(_ views: FakeTerminalViewSource) async throws -> (LinkClient, Collector<TerminalViewPush>) {
        let client = try await connect(makeHost(terminalViews: views))
        let pushes = collect(client.terminalPushes)
        _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
        return (client, pushes)
    }

    private func openWithSnapshot(history: [String]) async throws -> (LinkClient, Collector<TerminalViewPush>) {
        let views = FakeTerminalViewSource()
        // Wide enough for the longest row, which the screen would clip otherwise.
        let cols = max(20, history.map(\.count).max() ?? 0)
        views.onOpen("t-1") { view, _ in
            view.emit(.frame(snapshotFrame(cols: cols, rows: 2, text: ["s0", "s1"], history: history)))
        }
        return try await open(views)
    }

    private func firstFrameHead(_ pushes: Collector<TerminalViewPush>) async -> TerminalFrameHead? {
        _ = await waitFor(pushes) { $0.contains { if case .frame = $0 { return true } else { return false } } }
        for push in pushes.items { if case let .frame(_, part) = push { return part.head } }
        return nil
    }

    /// The encoded size of every part of every frame whose part 0 head is `.history`.
    private func historyFrameBytes(_ pushes: [TerminalViewPush]) throws -> Int {
        var total = 0
        var counting = false
        for push in pushes {
            guard case let .frame(id, part) = push else { continue }
            if part.part == 0 { counting = part.head?.kind == .history }
            if counting { total += try LinkCodec.encode(.terminalViewFrame(terminalId: id, frame: part)).count }
        }
        return total
    }
}
